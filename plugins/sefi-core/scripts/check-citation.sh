#!/usr/bin/env bash
# check-citation.sh <file>|-
#
# Deterministic pre-filter for a "verified against <file>:<line>" or "<file>:<start>-<end>"
# citation in a qa-engineer verdict -- catches the crudest half of citation fabrication for
# free, before engineering-manager spends a judgment call on it: a cited file that does not
# exist, or a cited line/range beyond the file's actual length, is impossible by
# construction, no reading required to know it is wrong.
#
# What this does NOT do, stated plainly rather than left implied: verify that the cited
# lines say what is CLAIMED. That is semantic, not mechanical. Found live, in a separate
# session running this repo's own main: a qa-engineer verdict cited "gate.sh lines 91-96"
# as proof that a pytest exit code was an accepted, documented case. Those lines were REAL
# and IN-BOUNDS -- this script would have passed that citation clean -- and still said
# nothing of the sort. This script closes the cruder half of that gap (impossible
# citations, free and instant); qa-engineer.md item 13 and engineering-manager.md item 7
# close the other half (read it yourself before citing it; spot-check before accepting it),
# because no script can substitute for actually reading the lines.
#
# Exit codes: 0 no impossible citation found; 1 one or more found; 2 usage error.
set -uo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "check-citation: usage: check-citation.sh <file>|-" >&2; exit 2; }

if [ "$SRC" = "-" ]; then
  TXT="$(cat)"
else
  [ -f "$SRC" ] || { echo "check-citation: $SRC not found" >&2; exit 2; }
  TXT="$(cat "$SRC")"
fi

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

errors=0
checked=0

resolve() {
  # resolve <path> -- echo the first existing candidate, or nothing.
  local p="$1"
  [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  [ -f "$ROOT/$p" ] && { printf '%s' "$ROOT/$p"; return 0; }
  [ -f "$CORE/$p" ] && { printf '%s' "$CORE/$p"; return 0; }
  return 1
}

while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  checked=$((checked + 1))
  path="${tok%%:*}"
  rest="${tok#*:}"
  case "$rest" in
    *-*) start="${rest%%-*}"; end="${rest##*-}" ;;
    *)   start="$rest"; end="$rest" ;;
  esac

  resolved="$(resolve "$path")" || {
    echo "check-citation: cited file '$path' does not exist (from '$tok')"
    errors=$((errors + 1))
    continue
  }

  total="$(wc -l < "$resolved")"
  if [ "$end" -gt "$total" ] 2>/dev/null; then
    echo "check-citation: cited '$tok' -- $path has only $total line(s)"
    errors=$((errors + 1))
  fi
done < <(printf '%s\n' "$TXT" | grep -ohE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?' | sort -u)

if [ "$errors" -ne 0 ]; then
  echo "check-citation: $errors impossible citation(s) -- file missing or line(s) out of range"
  exit 1
fi
echo "check-citation: OK ($checked citation(s) checked, all exist and are in bounds -- semantic correctness NOT verified, read them yourself)"
