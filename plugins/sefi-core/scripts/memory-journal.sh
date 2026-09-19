#!/usr/bin/env bash
# memory-journal.sh -- private, durable local nomination and close-session pipeline.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="config/sefi.config.yml"

python_bin=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then python_bin="$candidate"; break; fi
done
[ -n "$python_bin" ] || { echo 'memory-journal: Python is required' >&2; exit 1; }

fail() { echo "memory-journal: $*" >&2; return 1; }

cfg_get() {
  local key="$1" default="$2" value=""
  if [ -f "$CONFIG" ]; then
    value="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
  fi
  printf '%s' "${value:-$default}"
}

valid_component() {
  case "$1" in ''|.|..|*/*|*\\*|*..*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

session_dir() {
  valid_component "$1" || return 1
  printf '.sefi/journal/%s' "$1"
}

ensure_directory() {
  local dir="$1"
  [ ! -L "$dir" ] || return 1
  mkdir -p "$dir" || return 1
  [ -d "$dir" ] && [ ! -L "$dir" ]
}

ensure_journal_dir() {
  local id="$1" dir
  dir="$(session_dir "$id")" || return 1
  ensure_directory .sefi || return 1
  ensure_directory .sefi/journal || return 1
  ensure_directory "$dir" || return 1
  printf '%s' "$dir"
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

atomic_from_stdin() {
  local destination="$1" directory temporary
  directory="$(dirname "$destination")"
  [ -d "$directory" ] && [ ! -L "$directory" ] || return 1
  [ ! -L "$destination" ] || return 1
  temporary="$(mktemp "$directory/.memory-journal.XXXXXX")" || return 1
  if ! cat > "$temporary"; then rm -f -- "$temporary"; return 1; fi
  fsync_path "$temporary"
  if ! mv -f -- "$temporary" "$destination"; then rm -f -- "$temporary"; return 1; fi
  fsync_path "$destination"
  fsync_path "$directory"
}

atomic_string() { printf '%s\n' "$2" | atomic_from_stdin "$1"; }

lock_dir=""
acquire_lock() {
  local directory="$1" candidate owner tries=0
  candidate="$directory/.lock"
  while ! mkdir "$candidate" 2>/dev/null; do
    tries=$((tries + 1))
    owner="$(sed -n '1p' "$candidate/pid" 2>/dev/null || true)"
    if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
      rm -f -- "$candidate/pid" 2>/dev/null || true
      rmdir "$candidate" 2>/dev/null || true
      continue
    fi
    [ "$tries" -lt 100 ] || return 1
    sleep 0.05
  done
  printf '%s\n' "$$" > "$candidate/pid"
  lock_dir="$candidate"
}

release_lock() {
  [ -n "$lock_dir" ] || return 0
  rm -f -- "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
  lock_dir=""
}

utc_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

normal_title() {
  printf '%s' "$1" | tr -cs '[:alnum:]' ' ' | awk '{$1=$1; print}'
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

valid_title() {
  local normalized words
  normalized="$(normal_title "$1")"
  words="$(printf '%s\n' "$normalized" | awk '{print NF}')"
  [ "$words" = 2 ] || [ "$words" = 3 ]
}

project_slug() {
  local remote path owner repository fallback
  remote="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote" ]; then
    case "$remote" in
      *://*@*) remote="${remote##*@}" ;;
    esac
    case "$remote" in
      *:*) path="${remote##*:}" ;;
      */*) path="${remote#*://}"; path="${path#*/}" ;;
      *) path='' ;;
    esac
    path="${path%.git}"
    owner="$(printf '%s' "$path" | awk -F/ 'NF >= 2 { print $(NF - 1) }')"
    repository="$(printf '%s' "$path" | awk -F/ 'NF >= 2 { print $NF }')"
    if [ -n "$owner" ] && [ -n "$repository" ]; then
      slugify "$owner-$repository"
    else
      fallback="$(pwd -P)"
      slugify "$fallback"
    fi
  else
    fallback="$(pwd -P)"
    slugify "$fallback"
  fi
}

write_metadata() {
  local path="$1" id="$2" title="$3" status="$4" keywords="$5" projects="$6" notes="$7" project
  project="$(project_slug)"
  [ -n "$project" ] || project="unknown-project"
  {
    printf 'session-id=%s\n' "$id"
    printf 'title=%s\n' "$title"
    printf 'created-at=%s\n' "$(utc_iso)"
    printf 'project=%s\n' "$project"
    printf 'status=%s\n' "$status"
    printf 'keywords=%s\n' "$keywords"
    printf 'related-projects=%s\n' "$projects"
    printf 'related-notes=%s\n' "$notes"
  } | atomic_from_stdin "$path"
}

meta_value() { sed -n "s/^$2=//p" "$1" | head -1; }

yaml_quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

validate_vault() {
  VAULT="$(cfg_get vault_dir memory)"
  case "$VAULT" in ''|/*|*\\*|*..*|*//* ) return 1 ;; esac
  ensure_directory "$VAULT" || return 1
  [ ! -L "$VAULT" ]
}

close_session() {
  local id="$1" directory metadata cursor note_count facts note_body title created project status keywords projects notes year month filename target
  directory="$(session_dir "$id")" || return 1
  [ -d "$directory" ] && [ ! -L "$directory" ] || return 0
  acquire_lock "$directory" || { fail "could not obtain lock for $id"; return 1; }
  if [ -f "$directory/closed" ]; then release_lock; return 0; fi
  metadata="$directory/session.meta"
  if [ ! -f "$metadata" ] || [ -L "$metadata" ]; then release_lock; fail "missing session metadata for $id"; return 1; fi
  note_count="$(find "$directory" -maxdepth 1 -type f -name '[0-9]*.md' -print | wc -l | tr -d ' ')"
  if [ "$note_count" = 0 ]; then release_lock; return 0; fi
  facts="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-facts.XXXXXX")"
  if ! find "$directory" -maxdepth 1 -type f -name '[0-9]*.md' -print | LC_ALL=C sort | while IFS= read -r nomination; do
    bash "$HERE/memory-filter.sh" < "$nomination"
  done > "$facts"; then
    rm -f -- "$facts"; release_lock; return 1
  fi
  if [ ! -s "$facts" ]; then
    atomic_string "$directory/closed" 'skipped=empty-after-filter' || { rm -f -- "$facts"; release_lock; return 1; }
    find "$directory" -maxdepth 1 -type f -name '[0-9]*.md' -delete
    rm -f -- "$facts"; release_lock; return 0
  fi
  title="$(meta_value "$metadata" title)"
  created="$(meta_value "$metadata" created-at)"
  project="$(meta_value "$metadata" project)"
  status="$(meta_value "$metadata" status)"
  keywords="$(meta_value "$metadata" keywords)"
  projects="$(meta_value "$metadata" related-projects)"
  notes="$(meta_value "$metadata" related-notes)"
  valid_title "$title" || { rm -f -- "$facts"; release_lock; fail "invalid persisted title for $id"; return 1; }
  case "$status" in completed|partial|blocked) ;; *) status=partial ;; esac
  year="${created:0:4}"; month="${created:5:2}"
  [[ "$year" =~ ^[0-9]{4}$ && "$month" =~ ^[0-9]{2}$ ]] || { rm -f -- "$facts"; release_lock; fail "invalid creation time for $id"; return 1; }
  validate_vault || { rm -f -- "$facts"; release_lock; fail 'unsafe memory.vault_dir'; return 1; }
  ensure_directory "$VAULT/sessions" && ensure_directory "$VAULT/sessions/$year" && ensure_directory "$VAULT/sessions/$year/$month" || {
    rm -f -- "$facts"; release_lock; fail 'unsafe session-note directory'; return 1;
  }
  filename="${created:0:10}-${created:11:2}${created:14:2}-$(slugify "$title").md"
  target="$VAULT/sessions/$year/$month/$filename"
  [ ! -L "$target" ] || { rm -f -- "$facts"; release_lock; fail 'session-note destination is a symlink'; return 1; }
  if [ ! -e "$target" ]; then
    {
      printf '%s\n' '---'
      printf 'title: "%s"\n' "$(yaml_quote "$title")"
      printf 'created-at: "%s"\n' "$(yaml_quote "$created")"
      printf 'project: "%s"\n' "$(yaml_quote "$project")"
      printf 'session-id: "%s"\n' "$(yaml_quote "$id")"
      printf 'status: "%s"\n' "$(yaml_quote "$status")"
      printf 'keywords: "%s"\n' "$(yaml_quote "$keywords")"
      printf 'related-projects: "%s"\n' "$(yaml_quote "$projects")"
      printf 'related-notes: "%s"\n' "$(yaml_quote "$notes")"
      printf '%s\n' 'managed-by: sefi-agents'
      printf '%s\n\n' '---'
      printf '# %s\n\n' "$title"
      printf '%s\n%s\n\n' '## Context Summary' 'None'
      printf '%s\n%s\n\n' '## Result' 'None'
      printf '%s\n' '## Useful Information'
      sed 's/^/- /' "$facts"
      printf '\n%s\n%s\n\n' '## Why This Happened' 'Not applicable'
      printf '%s\n%s\n\n' '## Files Modified' 'None'
      printf '%s\n%s\n\n' '## Benefits' 'None'
      printf '%s\n%s\n\n' '## Tradeoffs and Limits' 'Not applicable'
      printf '%s\n%s\n' '## Follow-up' 'None'
    } | atomic_from_stdin "$target" || { rm -f -- "$facts"; release_lock; return 1; }
  fi
  rm -f -- "$facts"
  if ! bash "$HERE/gen-router.sh" >/dev/null; then release_lock; return 1; fi
  fsync_path "$VAULT/index.md"
  fsync_path "$VAULT"
  if [ "$(cfg_get cross_project_enabled false)" = true ]; then
    bash "$HERE/memory-cross-memory.sh" mirror "$target" >/dev/null 2>&1 || true
  fi
  atomic_string "$directory/closed" "note=$target" || { release_lock; return 1; }
  find "$directory" -maxdepth 1 -type f -name '[0-9]*.md' -delete
  release_lock
  printf '%s\n' "$target"
}

recover_sessions() {
  local directory id
  [ -d .sefi/journal ] && [ ! -L .sefi/journal ] || return 0
  while IFS= read -r directory; do
    id="$(basename "$directory")"
    [ -f "$directory/session.meta" ] && [ ! -f "$directory/closed" ] || continue
    find "$directory" -maxdepth 1 -type f -name '[0-9]*.md' -print -quit | grep -q . || continue
    close_session "$id" || return 1
  done < <(find .sefi/journal -mindepth 1 -maxdepth 1 -type d ! -type l -print | LC_ALL=C sort)
}

current_session() {
  local existing id uuid
  recover_sessions >/dev/null
  ensure_directory .sefi || return 1
  if [ -f .sefi/current-session ] && [ ! -L .sefi/current-session ]; then
    existing="$(sed -n '1p' .sefi/current-session)"
    if valid_component "$existing"; then printf '%s\n' "$existing"; return 0; fi
  fi
  uuid="$($python_bin -c 'import uuid; print(uuid.uuid4())')"
  id="$(date -u +%Y%m%dT%H%M%SZ)-$uuid"
  atomic_string .sefi/current-session "$id" || return 1
  printf '%s\n' "$id"
}

nominate() {
  local id='' kind='' title='' status='' keywords='' projects='' notes='' source='' directory metadata filtered cursor next existing_title
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session) id="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --status) status="${2:-}"; shift 2 ;;
      --keywords) keywords="${2:-}"; shift 2 ;;
      --related-projects) projects="${2:-}"; shift 2 ;;
      --related-notes) notes="${2:-}"; shift 2 ;;
      --file) source="${2:-}"; shift 2 ;;
      *) fail "unknown nomination argument: $1"; return 1 ;;
    esac
  done
  case "$kind" in greeting|casual|status|simple-fact) return 0 ;; substantive) ;; *) fail 'nomination kind must be substantive, greeting, casual, status, or simple-fact'; return 1 ;; esac
  [ -n "$source" ] && [ -f "$source" ] && [ ! -L "$source" ] || { fail 'substantive nomination requires a regular --file'; return 1; }
  valid_title "$title" || { fail 'session title must contain two or three words'; return 1; }
  case "$status" in completed|partial|blocked) ;; *) fail 'status must be completed, partial, or blocked'; return 1 ;; esac
  if [ -z "$id" ]; then id="$(current_session)"; fi
  valid_component "$id" || { fail 'unsafe session id'; return 1; }
  filtered="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-nomination.XXXXXX")"
  bash "$HERE/memory-filter.sh" < "$source" > "$filtered" || { rm -f -- "$filtered"; return 1; }
  if [ ! -s "$filtered" ]; then rm -f -- "$filtered"; return 0; fi
  directory="$(ensure_journal_dir "$id")" || { rm -f -- "$filtered"; fail 'unsafe journal directory'; return 1; }
  acquire_lock "$directory" || { rm -f -- "$filtered"; fail "could not obtain lock for $id"; return 1; }
  metadata="$directory/session.meta"
  if [ -f "$metadata" ]; then
    existing_title="$(meta_value "$metadata" title)"
    [ "$existing_title" = "$(normal_title "$title")" ] || { rm -f -- "$filtered"; release_lock; fail 'all session nominations require the same title'; return 1; }
  else
    write_metadata "$metadata" "$id" "$(normal_title "$title")" "$status" "$keywords" "$projects" "$notes" || {
      rm -f -- "$filtered"; release_lock; return 1;
    }
  fi
  cursor="$directory/cursor"
  next=0
  if [ -f "$cursor" ]; then
    next="$(sed -n '1p' "$cursor")"
    [[ "$next" =~ ^[0-9]+$ ]] || next=0
  fi
  next=$((next + 1))
  atomic_string "$cursor" "$next" || { rm -f -- "$filtered"; release_lock; return 1; }
  atomic_from_stdin "$directory/$(printf '%020d' "$next").md" < "$filtered" || {
    rm -f -- "$filtered"; release_lock; return 1;
  }
  rm -f -- "$filtered"
  release_lock
}

usage() {
  cat >&2 <<'EOF'
usage:
  memory-journal.sh nominate --session ID --kind KIND --title "two or three words" --status STATUS --keywords CSV --related-projects CSV --related-notes CSV --file FACTS
  memory-journal.sh close [--session ID]
  memory-journal.sh recover
  memory-journal.sh session-id
EOF
}

command="${1:-}"; shift || true
case "$command" in
  nominate) nominate "$@" ;;
  close)
    if [ "${1:-}" = --session ] && [ -n "${2:-}" ] && [ "$#" = 2 ]; then close_session "$2"; else
      [ "$#" = 0 ] || { usage; exit 2; }
      close_session "$(current_session)"
    fi ;;
  recover) [ "$#" = 0 ] || { usage; exit 2; }; recover_sessions ;;
  session-id) [ "$#" = 0 ] || { usage; exit 2; }; current_session ;;
  *) usage; exit 2 ;;
esac
