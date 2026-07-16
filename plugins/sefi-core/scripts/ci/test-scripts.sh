#!/usr/bin/env bash
# test-scripts.sh -- regression checks for the behavior scripts. Every assertion targets a
# specific failure mode found in the 2026-07-16 behavioral audit, per qa-engineer.md item 6
# ("Every fix you PASS must leave a regression test that asserts the specific failure mode
# traced during the fix") and software-engineer.md item 6 ("Non-trivial logic must leave one
# runnable check behind"). Not a smoke test: each case names the gap it guards.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
BUDGET_TPL="$CORE/templates/config/budget.yml"

fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

expect_code() {
  # expect_code <expected-exit> <label> <cmd...>
  local want="$1" label="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then ok "$label (exit $got)"; else bad "$label (expected exit $want, got $got)"; fi
}

echo "=== budget-check.sh (audit gap 8.1: the fail-open) ==="

# The fix: no ccusage AND no --spent means there is no spend source, so the cap cannot be
# checked and the gate must fail. Skipped when ccusage is installed locally; CI has no
# ccusage, and CI is the authority for this assertion.
if command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  echo "  SKIP: no-spend-source assertion (ccusage present locally; CI has none)"
else
  expect_code 1 "no ccusage + no --spent exits nonzero" \
    bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"
fi

# An explicit --spent 0 is a real claim of zero spend and must still pass.
expect_code 0 "explicit --spent 0 still passes" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 0 --config "$BUDGET_TPL"

# The pre-existing over-cap path must not regress: 3.00 against the template's 2.00 daily.
expect_code 1 "--spent 3.00 over the 2.00 daily cap exits nonzero" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 3.00 --config "$BUDGET_TPL"

echo
if [ "$fail" -ne 0 ]; then echo "test-scripts: $fail failed, $pass passed"; exit 1; fi
echo "test-scripts: OK ($pass passed)"
