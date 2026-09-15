#!/usr/bin/env bash
# Regression checks for maintenance-workflow safety invariants.  These checks are
# intentionally offline: they inspect the workflow contracts without invoking a provider.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
workflows=(
  "$ROOT/.github/workflows/triage.yml"
  "$ROOT/.github/workflows/triage-opencode.yml"
  "$ROOT/.github/workflows/retro.yml"
  "$ROOT/.github/workflows/retro-opencode.yml"
  "$ROOT/.github/workflows/sync.yml"
  "$ROOT/.github/workflows/sync-opencode.yml"
)
paid_workflows=(
  "$ROOT/.github/workflows/triage.yml"
  "$ROOT/.github/workflows/retro.yml"
  "$ROOT/.github/workflows/sync.yml"
)
free_workflows=(
  "$ROOT/.github/workflows/triage-opencode.yml"
  "$ROOT/.github/workflows/retro-opencode.yml"
  "$ROOT/.github/workflows/sync-opencode.yml"
)

fail=0
for workflow in "${workflows[@]}"; do
  name="$(basename "$workflow")"
  grep -Fqx '  contents: read' "$workflow" || { echo "FAIL: $name must default to read-only repository access" >&2; fail=1; }
  grep -Fq 'persist-credentials: false' "$workflow" || { echo "FAIL: $name must remove checkout credentials before model execution" >&2; fail=1; }
  grep -Fq 'permissions:' "$workflow" && grep -Fq '    contents: write' "$workflow" || { echo "FAIL: $name must grant write permission only to its publisher job" >&2; fail=1; }
  grep -Fqx '  group: sefi-maintenance' "$workflow" || { echo "FAIL: $name must share the maintenance concurrency group" >&2; fail=1; }
  if grep -Fq 'budget-check.sh --scope run --spent 0' "$workflow"; then
    echo "FAIL: $name must not certify an unmeasured run as zero spend" >&2
    fail=1
  fi
  if grep -Fq 'git push -u origin "$BRANCH"' "$workflow" && ! grep -Fq 'if: ${{ success()' "$workflow"; then
    echo "FAIL: $name may publish after a failed run" >&2
    fail=1
  fi
done

for workflow in "${paid_workflows[@]}"; do
  name="$(basename "$workflow")"
  grep -Fq 'uses: ./.github/actions/preflight-budget' "$workflow" || { echo "FAIL: $name must use the shared preflight budget gate" >&2; fail=1; }
  grep -Fq 'estimated-run-usd: ${{ inputs.estimated_run_usd || '"'"'0.50'"'"' }}' "$workflow" || { echo "FAIL: $name must pass its declared maximum run estimate to preflight" >&2; fail=1; }
  preflight_line="$(grep -n 'name: Preflight budget' "$workflow" | head -n 1 | cut -d: -f1)"
  provider_line="$(grep -n 'name: Run the ' "$workflow" | head -n 1 | cut -d: -f1)"
  [ -n "$preflight_line" ] && [ -n "$provider_line" ] && [ "$preflight_line" -lt "$provider_line" ] || { echo "FAIL: $name must run its preflight gate before the provider" >&2; fail=1; }
done

for workflow in "${free_workflows[@]}"; do
  name="$(basename "$workflow")"
  if grep -Fq 'uses: ./.github/actions/preflight-budget' "$workflow" || grep -Fq 'budget-check.sh --scope run' "$workflow"; then
    echo "FAIL: $name must not require spend telemetry for its free OpenCode Zen model" >&2
    fail=1
  fi
done

publisher="$ROOT/.github/actions/publish-state/action.yml"
grep -Fq 'find "$root" -mindepth 1 ! -type d ! -type f' "$publisher" || { echo "FAIL: publisher must reject non-regular candidate entries" >&2; fail=1; }
grep -Fq '<private>' "$publisher" || { echo "FAIL: publisher must reject private-tagged candidate content" >&2; fail=1; }
for workflow in "${workflows[@]}"; do
  name="$(basename "$workflow")"
  grep -Fq 'uses: ./.github/actions/publish-state' "$workflow" || { echo "FAIL: $name must use the shared validated publisher" >&2; fail=1; }
done

for workflow in "$ROOT/.github/workflows/triage.yml" "$ROOT/.github/workflows/triage-opencode.yml"; do
  name="$(basename "$workflow")"
  grep -Fq 'inputs.dry_run != true' "$workflow" || { echo "FAIL: $name must guard publication during a dry run" >&2; fail=1; }
done

exit "$fail"
