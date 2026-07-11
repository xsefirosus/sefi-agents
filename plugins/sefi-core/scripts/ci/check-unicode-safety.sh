#!/usr/bin/env bash
# check-unicode-safety.sh -- the Prompt Defense Baseline as code. Flag any non-ASCII
# codepoint (dangerous invisibles, bidi overrides, the Tag block, emoji/pictographs,
# em-dash, smart quotes, ellipsis) except the copyright/registered/trademark marks.
# Implemented with rg -P (PCRE2). Skips files > 100 KB (scan-performance guard).
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

# Forbidden = any codepoint outside ASCII, minus (c) U+00A9, (r) U+00AE, (tm) U+2122.
PAT='[^\x00-\x7F\x{00A9}\x{00AE}\x{2122}]'

errors=0
scanned=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  size="$(wc -c < "$f" 2>/dev/null || echo 0)"
  [ "${size:-0}" -gt 102400 ] && continue
  scanned=$((scanned + 1))
  hits="$(rg -nP "$PAT" "$f" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      echo "ERROR: $f - forbidden non-ASCII on: $hit"
      errors=$((errors + 1))
    done <<< "$hits"
  fi
done < <(targets)

if [ "$errors" -ne 0 ]; then echo "check-unicode-safety: $errors error(s)"; exit 1; fi
echo "check-unicode-safety: OK ($scanned files scanned, ASCII-clean)"
