#!/usr/bin/env bash
# memory-cross-memory.sh -- explicit, local-only cross-project memory controls and mirror.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG='config/sefi.config.yml'

python_bin=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then python_bin="$candidate"; break; fi
done
[ -n "$python_bin" ] || { echo 'memory-cross-memory: Python is required' >&2; exit 1; }

cfg_get() {
  local key="$1" default="$2" value=""
  if [ -f "$CONFIG" ]; then
    value="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
  fi
  printf '%s' "${value:-$default}"
}

safe_component() {
  case "$1" in ''|.|..|*/*|*\\*|*..*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

fsync_path() {
  "$python_bin" - "$1" <<'PY' >/dev/null 2>&1 || true
import os
import sys
try:
    fd = os.open(sys.argv[1], os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
except OSError:
    pass
PY
}

atomic_from_file() {
  local source="$1" destination="$2" directory temporary
  directory="$(dirname "$destination")"
  [ -d "$directory" ] && [ ! -L "$directory" ] && [ ! -L "$destination" ] || return 1
  temporary="$(mktemp "$directory/.memory-mirror.XXXXXX")" || return 1
  if ! cat "$source" > "$temporary"; then rm -f -- "$temporary"; return 1; fi
  fsync_path "$temporary"
  mv -f -- "$temporary" "$destination"
  fsync_path "$destination"
  fsync_path "$directory"
}

is_confirmed_local_machine() {
  [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ] && [ -z "${CODESPACES:-}" ] && [ -z "${IS_SANDBOX:-}" ] || return 1
  [ ! -f /.dockerenv ] || return 1
  case "$(uname -s 2>/dev/null || printf unknown)" in MINGW*|MSYS*|CYGWIN*|Darwin|Linux) ;; *) return 1 ;; esac
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    [ "$(systemd-detect-virt 2>/dev/null || true)" = none ] || return 1
  elif [ "$(uname -s 2>/dev/null || true)" = Linux ]; then
    return 1
  fi
  [ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ] && [ ! -L "$HOME" ]
}

shared_root() {
  [ "$(cfg_get cross_project_enabled false)" = true ] || return 1
  is_confirmed_local_machine || return 1
  local folder root
  folder="$(cfg_get cross_project_folder_name sefi-memory)"
  safe_component "$folder" || return 1
  root="$(cd "$HOME" && pwd -P)/$folder"
  [ ! -L "$root" ] || return 1
  printf '%s\n' "$root"
}

project_slug_for_mirror() {
  local remote path owner repository fallback
  remote="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote" ]; then
    case "$remote" in
      *://*@*|*gh[pousr]_*|*github_pat_*|*xox[baprs]-*|*AKIA*) return 1 ;;
    esac
    case "$remote" in
      *:*) path="${remote##*:}" ;;
      */*) path="${remote#*://}"; path="${path#*/}" ;;
      *) return 1 ;;
    esac
    path="${path%.git}"
    owner="$(printf '%s' "$path" | awk -F/ 'NF >= 2 { print $(NF - 1) }')"
    repository="$(printf '%s' "$path" | awk -F/ 'NF >= 2 { print $NF }')"
    [ -n "$owner" ] && [ -n "$repository" ] || return 1
    slugify "$owner-$repository"
  else
    fallback="$(pwd -P)"
    slugify "$fallback"
  fi
}

set_enabled() {
  local wanted="$1" temporary
  [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || { echo 'memory-cross-memory: config/sefi.config.yml is required' >&2; return 1; }
  temporary="$(mktemp "$(dirname "$CONFIG")/.sefi-config.XXXXXX")"
  if ! awk -v wanted="$wanted" '
    /^[[:space:]]*cross_project_enabled:[[:space:]]*/ {
      sub(/cross_project_enabled:[[:space:]]*[^[:space:]#]*/, "cross_project_enabled: " wanted)
      found=1
    }
    { print }
    END { exit(found ? 0 : 1) }
  ' "$CONFIG" > "$temporary"; then
    rm -f -- "$temporary"
    echo 'memory-cross-memory: memory.cross_project_enabled is missing' >&2
    return 1
  fi
  atomic_from_file "$temporary" "$CONFIG"
  rm -f -- "$temporary"
}

mirror_note() {
  local note="$1" root slug project_dir filename filtered destination
  [ -f "$note" ] && [ ! -L "$note" ] || { echo 'memory-cross-memory: mirror requires a regular note file' >&2; return 1; }
  root="$(shared_root)" || { echo 'memory-cross-memory: skipped (not explicitly enabled on a confirmed local machine)' >&2; return 1; }
  slug="$(project_slug_for_mirror)" || { echo 'memory-cross-memory: rejected credential-bearing remote' >&2; return 1; }
  safe_component "$slug" || { echo 'memory-cross-memory: rejected unnamed project' >&2; return 1; }
  filename="$(basename "$note")"
  safe_component "$filename" || { echo 'memory-cross-memory: rejected unsafe note path' >&2; return 1; }
  [ ! -L "$root" ] || { echo 'memory-cross-memory: rejected symlink mirror root' >&2; return 1; }
  mkdir -p "$root" || return 1
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  project_dir="$root/$slug"
  [ ! -L "$project_dir" ] || { echo 'memory-cross-memory: rejected symlink project path' >&2; return 1; }
  mkdir -p "$project_dir" || return 1
  [ -d "$project_dir" ] && [ ! -L "$project_dir" ] || return 1
  filtered="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-mirror-filtered.XXXXXX")"
  bash "$HERE/memory-filter.sh" < "$note" > "$filtered" || { rm -f -- "$filtered"; return 1; }
  destination="$project_dir/$filename"
  if [ -e "$destination" ]; then
    [ ! -L "$destination" ] && cmp -s "$filtered" "$destination" || {
      rm -f -- "$filtered"; echo 'memory-cross-memory: mirror destination conflict' >&2; return 1;
    }
  else
    atomic_from_file "$filtered" "$destination" || { rm -f -- "$filtered"; return 1; }
  fi
  rm -f -- "$filtered"
  printf '%s\n' "$destination"
}

command="${1:-}"; shift || true
case "$command" in
  enable) [ "$#" = 0 ] || exit 2; set_enabled true ;;
  disable) [ "$#" = 0 ] || exit 2; set_enabled false ;;
  status) [ "$#" = 0 ] || exit 2; [ "$(cfg_get cross_project_enabled false)" = true ] && echo enabled || echo disabled ;;
  root) [ "$#" = 0 ] || exit 2; shared_root ;;
  mirror) [ "$#" = 1 ] || { echo 'usage: memory-cross-memory.sh mirror <note>' >&2; exit 2; }; mirror_note "$1" ;;
  *) echo 'usage: memory-cross-memory.sh enable|disable|status|mirror <note>' >&2; exit 2 ;;
esac
