#!/usr/bin/env bash
# memory-index.sh -- rebuild or check the disposable local manifest over session
# notes and ignored-local audit reports.
set -euo pipefail

CONFIG="config/sefi.config.yml"

python_bin=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then python_bin="$candidate"; break; fi
done
[ -n "$python_bin" ] || { echo 'memory-index: Python is required' >&2; exit 1; }

cfg_get() {
  local key="$1" default="$2" value=""
  if [ -f "$CONFIG" ]; then
    value="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
  fi
  printf '%s' "${value:-$default}"
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
  temporary="$(mktemp "$directory/.memory-index.XXXXXX")" || return 1
  if ! cat "$source" > "$temporary"; then rm -f -- "$temporary"; return 1; fi
  fsync_path "$temporary"
  mv -f -- "$temporary" "$destination"
  fsync_path "$destination"
  fsync_path "$directory"
}

sha_file() {
  "$python_bin" - "$1" <<'PY'
import hashlib
import sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as source:
    for block in iter(lambda: source.read(1024 * 1024), b''):
        h.update(block)
print(h.hexdigest())
PY
}

sha_text() {
  "$python_bin" -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

vault="$(cfg_get vault_dir memory)"
case "$vault" in ''|/*|*\\*|*..*|*//* ) echo 'memory-index: unsafe memory.vault_dir' >&2; exit 1 ;; esac
[ ! -L "$vault" ] || { echo 'memory-index: vault cannot be a symlink' >&2; exit 1; }
index_dir='.sefi/memory-index'
manifest="$index_dir/manifest.json"

build_manifest() {
  local sources line path hash cursor first=1
  sources="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-index-sources.XXXXXX")"
  trap 'rm -f "$sources"' RETURN
  if [ -d "$vault/sessions" ] && [ ! -L "$vault/sessions" ]; then
    while IFS= read -r -d '' note; do
      [ ! -L "$note" ] || continue
      path="${note#"$vault"/}"
      hash="$(sha_file "$note")"
      printf '%s\t%s\n' "$path" "$hash" >> "$sources"
    done < <(find "$vault/sessions" -type f ! -type l -name '*.md' -print0 | LC_ALL=C sort -z)
  fi
  if [ -d audits ] && [ ! -L audits ]; then
    while IFS= read -r -d '' note; do
      [ ! -L "$note" ] || continue
      path="${note#./}"
      hash="$(sha_file "$note")"
      printf '%s\t%s\n' "$path" "$hash" >> "$sources"
    done < <(find audits -maxdepth 1 -type f ! -type l -name 'audit-report-*.md' -print0 | LC_ALL=C sort -z)
  fi
  cursor="$(sha_text < "$sources")"
  printf '%s\n' '{'
  printf '  "format": "memory-index-v1",\n'
  printf '  "cursor": "%s",\n' "$cursor"
  printf '%s\n' '  "sources": ['
  while IFS=$'\t' read -r path hash; do
    [ -n "$path" ] || continue
    if [ "$first" = 0 ]; then printf ',\n'; fi
    first=0
    printf '    {"path":"%s","sha256":"%s"}' "$(json_escape "$path")" "$hash"
  done < "$sources"
  printf '\n%s\n' '  ]'
  printf '%s\n' '}'
  rm -f -- "$sources"
  trap - RETURN
}

command="${1:-}"
case "$command" in
  rebuild)
    [ "$#" = 1 ] || { echo 'usage: memory-index.sh rebuild|status' >&2; exit 2; }
    [ ! -L .sefi ] || { echo 'memory-index: .sefi cannot be a symlink' >&2; exit 1; }
    mkdir -p "$index_dir"
    [ -d "$index_dir" ] && [ ! -L "$index_dir" ] || { echo 'memory-index: unsafe index directory' >&2; exit 1; }
    expected="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-index.XXXXXX")"
    build_manifest > "$expected"
    atomic_from_file "$expected" "$manifest"
    rm -f -- "$expected"
    printf 'rebuilt %s\n' "$manifest"
    ;;
  status)
    [ "$#" = 1 ] || { echo 'usage: memory-index.sh rebuild|status' >&2; exit 2; }
    if [ ! -f "$manifest" ] || [ -L "$manifest" ]; then echo 'stale: index missing'; exit 1; fi
    expected="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-index.XXXXXX")"
    build_manifest > "$expected"
    if cmp -s "$expected" "$manifest"; then
      rm -f -- "$expected"
      echo 'fresh'
    else
      rm -f -- "$expected"
      echo 'stale: rebuild required'
      exit 1
    fi
    ;;
  *) echo 'usage: memory-index.sh rebuild|status' >&2; exit 2 ;;
esac
