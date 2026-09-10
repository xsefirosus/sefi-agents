#!/usr/bin/env bash
# test-triage-workflow-safety.sh -- byte-for-byte gate for the reviewed triage boundary.
# The fixture is intentionally the authority: do not add a YAML parser here. A workflow
# change must be reviewed by changing the fixture and this test in the same security review.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/triage-opencode.yml"
FIXTURE="$ROOT/plugins/sefi-core/scripts/ci/fixtures/triage-opencode.safe.yml"
INIT="$ROOT/plugins/sefi-core/commands/init.md"
TEMPLATE_DIR="$ROOT/plugins/sefi-core/templates/workflows"

fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== OpenCode triage workflow safety ==="

if [ ! -f "$FIXTURE" ]; then
  bad "reviewed safe workflow fixture exists"
elif [ ! -f "$WORKFLOW" ]; then
  bad "workflow exists at .github/workflows/triage-opencode.yml"
elif cmp -s "$FIXTURE" "$WORKFLOW"; then
  ok "workflow exactly matches reviewed safe fixture"
else
  bad "workflow differs from reviewed safe fixture"
  # Both files are repository-controlled workflow source with secret references only; never
  # print runtime secrets. Keep the mismatch diagnostic short enough for CI logs.
  diff -u --label reviewed-safe-fixture --label current-workflow "$FIXTURE" "$WORKFLOW" \
    | sed -n '1,80p' || true
fi

if [ ! -f "$INIT" ]; then
  bad "init command exists for template-reference check"
elif rg -Fq 'templates/workflows/' "$INIT"; then
  bad "init does not reference a workflow template distribution path"
else
  ok "init does not reference a workflow template distribution path"
fi

if [ -d "$TEMPLATE_DIR" ] && find "$TEMPLATE_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print -quit | rg -q .; then
  bad "no YAML workflow template is distributed from templates/workflows"
else
  ok "no YAML workflow template is distributed from templates/workflows"
fi

if [ "$fail" -ne 0 ]; then
  echo "triage-workflow-safety: FAILED ($fail failed, $pass passed)" >&2
  exit 1
fi

echo "triage-workflow-safety: PASS ($pass passed)"
