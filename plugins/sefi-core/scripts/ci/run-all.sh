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
validate-doc-counts.sh
validate-loops.sh
validate-budget.sh
validate-config-wired.sh
validate-no-personal-paths.sh
validate-no-orphans.sh
validate-links.sh
validate-script-refs.sh
validate-release-ledger.sh
validate-routing.sh
validate-model-map.sh
validate-adapters.sh
validate-rule-presence.sh
check-unicode-safety.sh
validate-comment-safety.sh
validate-token-budget.sh
test-scripts.sh
test-integration.sh
test-opencode-schedule-ownership.sh
test-workflow-safety.sh
test-ci-coverage.sh
test-shared-memory-safety.sh
test-runtime-contracts.sh
test-v08-durability.sh
test-v08-conformance.sh
test-memory-journalist.sh
test-onboarding-v08.sh
test-agent-capabilities-v08.sh
test-design-council.sh
test-design-council-routing.sh
test-v09-documentation.sh
test-cartographer-v091.sh
test-cartographer-runtime-v091.sh
test-documentation-grounding-v091.sh
test-benchmark-oracles.sh
test-release-strict.sh
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

python_bin=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
if [ -z "$python_bin" ]; then
  echo "CI: Python 3.11+ is required for benchmark tests" >&2
  fail=1
elif ! "$python_bin" -m unittest discover -s benchmarks -p 'test_*.py'; then
  fail=1
fi

while IFS= read -r script; do
  if ! bash -n "$script"; then
    echo "CI: shell syntax check failed: $script" >&2
    fail=1
  fi
done < <(git ls-files '*.sh')

if [ "$fail" -ne 0 ]; then
  echo "CI: FAILED -- one or more validators reported errors" >&2
  exit 1
fi
echo "CI: all validators passed" >&2
exit 0
