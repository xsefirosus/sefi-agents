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

expect_full_loop() {
  local workflow="$1" label="$2"
  if grep -Fq '      - name: Commit state (never auto-merge' "$workflow" \
    && grep -Fq 'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' "$workflow" \
    && grep -Fq 'git push -u origin "$BRANCH"' "$workflow" \
    && grep -Fq 'gh pr create' "$workflow"; then
    ok "$label OpenCode workflow retains full branch-and-PR behavior"
  else
    bad "$label OpenCode workflow retains full branch-and-PR behavior"
  fi
}

# `inbox/` is optional: a discovery-only loop normally changes only state/. Git exits 128
# when asked to add a path that does not exist, so every loop must stage state/memory first
# and include inbox only when it is present.
expect_safe_state_staging() {
  local workflow="$1" label="$2"
  if ! grep -Fq 'git add state/ memory/ inbox/' "$workflow" \
    && grep -Fq 'git add state/ memory/' "$workflow" \
    && grep -Fq 'if [ -d inbox ]; then' "$workflow" \
    && grep -Fq 'git add inbox/' "$workflow"; then
    ok "$label safely stages the optional inbox directory"
  else
    bad "$label does not safely stage the optional inbox directory"
  fi
}

echo "=== OpenCode schedule ownership ==="

expect_schedule "$ROOT/.github/workflows/triage-opencode.yml" '0 6 * * *' 'morning-triage'
expect_schedule "$ROOT/.github/workflows/retro-opencode.yml" '0 7 * * 1' 'weekly-retro'
expect_schedule "$ROOT/.github/workflows/sync-opencode.yml" '0 8 * * 1' 'sync'
expect_no_schedule "$ROOT/.github/workflows/triage.yml" 'morning-triage'
expect_no_schedule "$ROOT/.github/workflows/retro.yml" 'weekly-retro'
expect_no_schedule "$ROOT/.github/workflows/sync.yml" 'sync'
expect_full_loop "$ROOT/.github/workflows/triage-opencode.yml" 'morning-triage'
expect_full_loop "$ROOT/.github/workflows/retro-opencode.yml" 'weekly-retro'
expect_full_loop "$ROOT/.github/workflows/sync-opencode.yml" 'sync'
expect_safe_state_staging "$ROOT/.github/workflows/triage.yml" 'morning-triage Claude workflow'
expect_safe_state_staging "$ROOT/.github/workflows/retro.yml" 'weekly-retro Claude workflow'
expect_safe_state_staging "$ROOT/.github/workflows/sync.yml" 'sync Claude workflow'
expect_safe_state_staging "$ROOT/.github/workflows/triage-opencode.yml" 'morning-triage OpenCode workflow'
expect_safe_state_staging "$ROOT/.github/workflows/retro-opencode.yml" 'weekly-retro OpenCode workflow'
expect_safe_state_staging "$ROOT/.github/workflows/sync-opencode.yml" 'sync OpenCode workflow'

if [ "$fail" -ne 0 ]; then
  echo "opencode-schedule-ownership: FAILED ($fail failed, $pass passed)" >&2
  exit 1
fi

echo "opencode-schedule-ownership: PASS ($pass passed)"
