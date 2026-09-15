#!/usr/bin/env bash
# test-opencode-schedule-ownership.sh -- each recurring loop has one OpenCode cron owner.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

expect_schedule() {
  local workflow="$1" cron="$2" label="$3"
  if grep -Fqx '  schedule:' "$workflow" && grep -Fqx "    - cron: \"$cron\"" "$workflow"; then
    ok "$label OpenCode workflow owns cron $cron"
  else
    bad "$label OpenCode workflow owns cron $cron"
  fi
}

expect_no_schedule() {
  local workflow="$1" label="$2"
  if grep -Fqx '  schedule:' "$workflow"; then
    bad "$label Claude workflow has no cron"
  else
    ok "$label Claude workflow has no cron"
  fi
}

expect_publisher_handoff() {
  local workflow="$1" label="$2"
  if grep -Fq 'uses: ./.github/actions/publish-state' "$workflow" \
    && grep -Fq 'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' "$workflow"; then
    ok "$label OpenCode workflow hands state to the validated publisher"
  else
    bad "$label OpenCode workflow does not hand state to the validated publisher"
  fi
}

# `inbox/` is optional. State staging belongs to the publisher action so every workflow
# gets the same guarded behavior and candidate validation.
expect_safe_publisher_staging() {
  local publisher="$ROOT/.github/actions/publish-state/action.yml"
  if grep -Fq 'git add -A -- state/ memory/ inbox/ 2>/dev/null || true' "$publisher" \
    && grep -Fq 'find "$root" -mindepth 1 ! -type d ! -type f' "$publisher"; then
    ok "validated publisher safely stages optional state directories"
  else
    bad "validated publisher does not safely stage optional state directories"
  fi
}

echo "=== OpenCode schedule ownership ==="

expect_schedule "$ROOT/.github/workflows/triage-opencode.yml" '0 6 * * *' 'morning-triage'
expect_schedule "$ROOT/.github/workflows/retro-opencode.yml" '0 7 * * 1' 'weekly-retro'
expect_schedule "$ROOT/.github/workflows/sync-opencode.yml" '0 8 * * 1' 'sync'
expect_no_schedule "$ROOT/.github/workflows/triage.yml" 'morning-triage'
expect_no_schedule "$ROOT/.github/workflows/retro.yml" 'weekly-retro'
expect_no_schedule "$ROOT/.github/workflows/sync.yml" 'sync'
expect_publisher_handoff "$ROOT/.github/workflows/triage-opencode.yml" 'morning-triage'
expect_publisher_handoff "$ROOT/.github/workflows/retro-opencode.yml" 'weekly-retro'
expect_publisher_handoff "$ROOT/.github/workflows/sync-opencode.yml" 'sync'
expect_safe_publisher_staging

for workflow in \
  "$ROOT/.github/workflows/triage-opencode.yml" \
  "$ROOT/.github/workflows/retro-opencode.yml" \
  "$ROOT/.github/workflows/sync-opencode.yml"; do
  name="$(basename "$workflow")"
  if grep -Fqx '        default: opencode/muse-spark-1.3-contributor-free' "$workflow" \
    && grep -Fq 'MODEL="${MODEL:-opencode/muse-spark-1.3-contributor-free}"' "$workflow" \
    && ! grep -Fq 'muse-spark-1.2-contributor-free' "$workflow"; then
    ok "$name uses Muse Spark 1.3 Contributor Free by default and fallback"
  else
    bad "$name must use Muse Spark 1.3 Contributor Free by default and fallback"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "opencode-schedule-ownership: FAILED ($fail failed, $pass passed)" >&2
  exit 1
fi

echo "opencode-schedule-ownership: PASS ($pass passed)"
