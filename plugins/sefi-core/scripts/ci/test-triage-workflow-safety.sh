#!/usr/bin/env bash
# test-triage-workflow-safety.sh -- pins the OpenCode triage workflow's privilege boundary.
# This deliberately-static test rejects broadening the discovery job or returning OpenCode
# capabilities to the manual publisher. Keep the awk ranges tied to job/step indentation so
# a safe value in a different job cannot satisfy a discovery assertion.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/triage-opencode.yml"
TEMPLATE="$ROOT/plugins/sefi-core/templates/workflows/triage-opencode.yml"
INIT="$ROOT/plugins/sefi-core/commands/init.md"

fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

expect() {
  # expect <label> <command...>
  local label="$1"
  shift
  if "$@"; then
    ok "$label"
  else
    bad "$label"
  fi
}

echo "=== OpenCode triage workflow safety ==="

if [ ! -f "$WORKFLOW" ]; then
  bad "workflow exists at .github/workflows/triage-opencode.yml"
else
  expect "workflow_dispatch is the only supported trigger" \
    awk '
      $0 == "on:" { in_on = 1; next }
      in_on && $0 ~ /^[^[:space:]#]/ { in_on = 0 }
      in_on && $0 ~ /^  workflow_dispatch:[[:space:]]*(#.*)?$/ { dispatch = 1 }
      in_on && $0 ~ /^  schedule:[[:space:]]*(#.*)?$/ { schedule = 1 }
      END { exit !(dispatch && !schedule) }
    ' "$WORKFLOW"

  for action in \
    'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' \
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' \
    'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'; do
    expect "workflow uses exact pin $action" \
      awk -v expected="$action" '
        {
          line = $0
          sub(/^[[:space:]]*/, "", line)
          sub(/[[:space:]]*(#.*)?$/, "", line)
          if (line == "uses: " expected) found = 1
        }
        END { exit !found }
      ' "$WORKFLOW"
  done

  expect "publisher uses the exact manual-dispatch condition" \
    awk '
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*(#.*)?$/, "", line)
        if (line == "if: github.event_name == '\''workflow_dispatch'\'' && inputs.publish_report == true") found = 1
      }
      END { exit !found }
    ' "$WORKFLOW"

  expect "discover permissions are exactly actions, contents, and issues read" \
    awk '
      /^  discover:[[:space:]]*(#.*)?$/ { discover = 1; next }
      discover && /^  [^[:space:]#][^:]*:/ { discover = 0; permissions = 0 }
      discover && /^    permissions:[[:space:]]*(#.*)?$/ { permissions = 1; saw_permissions = 1; next }
      permissions && /^    [^[:space:]#][^:]*:/ { permissions = 0 }
      permissions && /^      actions:[[:space:]]*read[[:space:]]*(#.*)?$/ { actions++; next }
      permissions && /^      contents:[[:space:]]*read[[:space:]]*(#.*)?$/ { contents++; next }
      permissions && /^      issues:[[:space:]]*read[[:space:]]*(#.*)?$/ { issues++; next }
      permissions && /^      [^[:space:]#][^:]*:/ { unexpected = 1 }
      END {
        exit !(saw_permissions && actions == 1 && contents == 1 && issues == 1 && !unexpected)
      }
    ' "$WORKFLOW"

  expect "discover checkout disables persisted credentials" \
    awk '
      function finish_step() {
        if (checkout && no_credentials) safe_checkout = 1
        checkout = 0
        no_credentials = 0
      }
      /^  discover:[[:space:]]*(#.*)?$/ { discover = 1; next }
      discover && /^  [^[:space:]#][^:]*:/ { finish_step(); discover = 0 }
      discover && /^      - / { finish_step(); next }
      discover && /^[[:space:]]*uses:[[:space:]]*actions\/checkout@11bd71901bbe5b1630ceea73d27597364c9af683[[:space:]]*(#.*)?$/ { checkout = 1 }
      discover && /^[[:space:]]*persist-credentials:[[:space:]]*false[[:space:]]*(#.*)?$/ { no_credentials = 1 }
      END { finish_step(); exit !safe_checkout }
    ' "$WORKFLOW"

  expect "discover OpenCode step has no GH_TOKEN or GITHUB_TOKEN" \
    awk '
      function finish_step() {
        if (opencode) {
          saw_opencode = 1
          if (github_token) unsafe_opencode = 1
        }
        opencode = 0
        github_token = 0
      }
      /^  discover:[[:space:]]*(#.*)?$/ { discover = 1; next }
      discover && /^  [^[:space:]#][^:]*:/ { finish_step(); discover = 0 }
      discover && /^      - / { finish_step(); next }
      discover && /^[[:space:]]*(GH_TOKEN|GITHUB_TOKEN):/ { github_token = 1 }
      discover && /^[[:space:]]+opencode[[:space:]]+run([[:space:]]|$)/ { opencode = 1 }
      END { finish_step(); exit !(saw_opencode && !unsafe_opencode) }
    ' "$WORKFLOW"

  expect "publish-report contains no Zen credential or OpenCode command" \
    awk '
      /^  publish-report:[[:space:]]*(#.*)?$/ { publisher = 1; found_publisher = 1; next }
      publisher && /^  [^[:space:]#][^:]*:/ { publisher = 0 }
      publisher && /^[[:space:]]*OPENCODE_ZEN_API_KEY:/ { unsafe = 1 }
      publisher && /^[[:space:]]+opencode[[:space:]]+run([[:space:]]|$)/ { unsafe = 1 }
      END { exit !(found_publisher && !unsafe) }
    ' "$WORKFLOW"
fi

if [ ! -e "$TEMPLATE" ]; then
  ok "repository-specific OpenCode workflow template is absent"
else
  bad "repository-specific OpenCode workflow template is absent"
fi

if [ ! -f "$INIT" ]; then
  bad "init command exists for template-reference check"
elif rg -Fq 'templates/workflows/triage-opencode.yml' "$INIT"; then
  bad "init does not copy the repository-specific OpenCode workflow template"
else
  ok "init does not copy the repository-specific OpenCode workflow template"
fi

if [ "$fail" -ne 0 ]; then
  echo "triage-workflow-safety: FAILED ($fail failed, $pass passed)" >&2
  exit 1
fi

echo "triage-workflow-safety: PASS ($pass passed)"
