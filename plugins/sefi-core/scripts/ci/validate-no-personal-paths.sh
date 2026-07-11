#!/usr/bin/env bash
# validate-no-personal-paths.sh -- scan shipped files for /Users/<name> and
# C:\Users\<name> home paths; angle-bracket placeholders and common placeholder words are
# allowlisted. Planning docs under docs/ (master prompt, provenance, archive) are excluded.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

targets() {
  for d in .claude-plugin plugins adapters; do [ -d "$d" ] && find "$d" -type f; done
  for f in docs/LOOPS.md docs/ANTIPATTERNS.md docs/CHECKLIST.md docs/BUDGET.md docs/OPTIONAL-TOOLS.md \
           README.md Install.md CHANGELOG.md LICENSE install.sh; do
    [ -f "$f" ] && echo "$f"
  done
}

pat_unix='/Users/[A-Za-z0-9._-]+'
pat_win='[A-Za-z]:\\Users\\[A-Za-z0-9._ -]+'

is_placeholder() {
  case "$1" in
    name|user|username|USERNAME|USER|you|YOU|YourName|yourname|home|Home) return 0 ;;
    *) return 1 ;;
  esac
}

hits="$(
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    rg -oN "$pat_unix" "$f" 2>/dev/null | sed "s#^#${f}|#"
    rg -oN "$pat_win"  "$f" 2>/dev/null | sed "s#^#${f}|#"
  done < <(targets)
)"

errors=0
if [ -n "$hits" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%|*}"
    match="${line#*|}"
    name="$(printf '%s' "$match" | sed -E 's#.*Users[\\/]([A-Za-z0-9._ -]+).*#\1#')"
    is_placeholder "$name" && continue
    echo "ERROR: $file - personal path detected: $match"
    errors=$((errors + 1))
  done <<< "$hits"
fi

if [ "$errors" -ne 0 ]; then echo "validate-no-personal-paths: $errors error(s)"; exit 1; fi
echo "validate-no-personal-paths: OK (no personal paths in shipped files)"
