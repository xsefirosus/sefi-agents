#!/usr/bin/env bash
# run-all.sh -- single entry point for the CI validation suite. Runs every validator,
# aggregates results, and exits 1 if any reported an error. Pass --strict (or set
# CI_STRICT=1) to promote frontmatter-quality warnings to errors.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ARGS=""
[ "${1:-}" = "--strict" ] && ARGS="--strict"
[ "${CI_STRICT:-0}" = "1" ] && ARGS="--strict"

validators="
validate-agents.sh
validate-skills.sh
validate-loops.sh
validate-budget.sh
validate-no-personal-paths.sh
validate-no-orphans.sh
check-unicode-safety.sh
validate-token-budget.sh
"

fail=0
for v in $validators; do
  echo "=== $v ==="
  if bash "$HERE/$v" $ARGS; then
    :
  else
    fail=1
  fi
  echo
done

if [ "$fail" -ne 0 ]; then
  echo "CI: FAILED -- one or more validators reported errors" >&2
  exit 1
fi
echo "CI: all validators passed" >&2
exit 0
