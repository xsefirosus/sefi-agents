#!/usr/bin/env bash
# memory-search.sh -- rank local session notes and ignored-local audit reports;
# cross-project reads require a named opt-in. Audit reports never enter the
# cross-project mirror, so the audits/ tree is searched only for local queries.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG='config/sefi.config.yml'

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

matches() { printf '%s\n' "$1" | grep -F -i -q -- "$query"; }

frontmatter() {
  awk 'NR==1 && $0!="---" { exit } NR==1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1"
}

body() {
  awk 'NR==1 { if ($0=="---") { fm=1; next } } fm && /^---[[:space:]]*$/ { fm=0; next } !fm { print }' "$1"
}

field() { printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1; }

rank_note() {
  local note="$1" shown="$2" fm title keywords related created note_body score=0
  fm="$(frontmatter "$note")"
  title="$(field "$fm" title)"
  keywords="$(field "$fm" keywords)"
  related="$(field "$fm" related-projects) $(field "$fm" related-notes)"
  created="$(field "$fm" created-at)"
  if matches "$title"; then score=400; elif matches "$keywords"; then score=390; elif matches "$related"; then score=200; else
    note_body="$(body "$note")"
    matches "$note_body" && score=100
  fi
  [ "$score" -gt 0 ] || return 0
  printf '%s|%s|%s\n' "$score" "${created:-0000-00-00T00:00:00Z}" "$shown"
}

search_tree() {
  local base="$1" display_prefix="$2" note relative
  [ -d "$base" ] && [ ! -L "$base" ] || return 0
  while IFS= read -r -d '' note; do
    [ ! -L "$note" ] || continue
    relative="${note#"$base"/}"
    rank_note "$note" "${display_prefix}${relative}"
  done < <(find "$base" -type f ! -type l -name '*.md' -print0 | LC_ALL=C sort -z)
}

query="${1:-}"
[ -n "$query" ] || { echo 'usage: memory-search.sh <query> [--project <slug>]' >&2; exit 2; }
shift
project=''
if [ "$#" -gt 0 ]; then
  [ "$#" = 2 ] && [ "$1" = --project ] || { echo 'usage: memory-search.sh <query> [--project <slug>]' >&2; exit 2; }
  project="$2"
  safe_component "$project" || { echo 'memory-search: --project must be a safe named project slug' >&2; exit 2; }
fi

results="$(mktemp "${TMPDIR:-/tmp}/sefi-memory-search.XXXXXX")"
trap 'rm -f "$results"' EXIT
if [ -n "$project" ]; then
  [ "$(cfg_get cross_project_enabled false)" = true ] || {
    echo 'memory-search: cross-project memory is disabled' >&2; exit 1;
  }
  shared_root="$(bash "$HERE/memory-cross-memory.sh" root 2>/dev/null)" || {
    echo 'memory-search: cross-project memory is unavailable on this machine' >&2; exit 1;
  }
  [ ! -L "$shared_root" ] && [ ! -L "$shared_root/$project" ] || {
    echo 'memory-search: unsafe cross-project path' >&2; exit 1;
  }
  search_tree "$shared_root/$project" "cross:$project/" > "$results"
else
  vault="$(cfg_get vault_dir memory)"
  case "$vault" in ''|/*|*\\*|*..*|*//* ) echo 'memory-search: unsafe memory.vault_dir' >&2; exit 1 ;; esac
  [ ! -L "$vault" ] || { echo 'memory-search: vault cannot be a symlink' >&2; exit 1; }
  search_tree "$vault/sessions" "$vault/sessions/" > "$results"
  search_tree "audits" "audits/" >> "$results"
fi

sort -t '|' -k1,1nr -k2,2r -k3,3 "$results" | cut -d '|' -f3-
