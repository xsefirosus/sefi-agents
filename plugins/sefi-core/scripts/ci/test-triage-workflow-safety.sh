#!/usr/bin/env bash
# test-triage-workflow-safety.sh -- fail-closed grammar for the triage privilege boundary.
#
# This is intentionally not a general YAML parser. It accepts only the normal block-YAML
# layout emitted by this repository's triage workflow. A new YAML shape is a security review
# event: reject it here rather than guessing how flow syntax, quotes, aliases, or duplicate
# keys should be interpreted.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/triage-opencode.yml"
INIT="$ROOT/plugins/sefi-core/commands/init.md"
TEMPLATE_DIR="$ROOT/plugins/sefi-core/templates/workflows"

CHECKOUT='actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683'
UPLOAD='actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
DOWNLOAD='actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
PUBLISH_IF="if: github.event_name == 'workflow_dispatch' && inputs.publish_report == true"

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

check_pinned_occurrences() {
  # check_pinned_occurrences <action> <sha> <expected-normal-occurrences>
  local action="$1" sha="$2" expected_count="$3"
  awk -v action="$action" -v literal="uses: $action@$sha" -v expected_count="$expected_count" '
    function count(text, needle, n, pos) {
      n = 0
      while ((pos = index(text, needle)) != 0) {
        n++
        text = substr(text, pos + length(needle))
      }
      return n
    }
    {
      raw += count($0, action)
      exact += count($0, literal)
    }
    END {
      if (raw == 0) {
        print "missing required action: " action > "/dev/stderr"
        exit 1
      }
      if (raw != exact || raw != expected_count) {
        print "unsupported workflow form: " action " has " raw \
              " raw occurrence(s), " exact " exact normal pinned occurrence(s); expected " \
              expected_count > "/dev/stderr"
        exit 1
      }
    }
  ' "$WORKFLOW"
}

check_canonical_workflow() {
  awk -v checkout="$CHECKOUT" -v upload="$UPLOAD" -v download="$DOWNLOAD" \
      -v publish_if="$PUBLISH_IF" '
    function unsupported(message) {
      print "unsupported workflow form: " message > "/dev/stderr"
      invalid = 1
    }
    function finish_step() {
      if (!in_step) return

      if (step_name == "Prefetch triage input") {
        prefetch_steps++
        if (step_uses != "") unsupported("Prefetch triage input may not use an action")
      } else if (step_has_github_token) {
        unsupported("GH_TOKEN/GITHUB_TOKEN appears outside the fixed Prefetch triage input step")
      }

      if (step_has_opencode) {
        opencode_steps++
        if (step_has_github_token) {
          unsupported("OpenCode step contains a GitHub-token variable or secret reference")
        }
      }

      if (step_uses == "checkout") {
        discover_checkouts++
        if (with_count != 1 || persist_false_count != 1 || bad_persist) {
          unsupported("every discover checkout needs its own normal with: block and persist-credentials: false")
        }
      } else if (step_uses == "upload") {
        discover_uploads++
      } else if (step_uses != "") {
        unsupported("unsupported action in discover")
      }

      in_step = 0
      step_name = ""
      step_uses = ""
      with_count = 0
      in_with = 0
      persist_false_count = 0
      bad_persist = 0
      step_has_github_token = 0
      step_has_opencode = 0
    }
    function classify_discover_uses(value) {
      if (step_uses != "") {
        unsupported("a discover step declares more than one uses: action")
      } else if (value == checkout) {
        step_uses = "checkout"
      } else if (value == upload) {
        step_uses = "upload"
      } else {
        unsupported("discover uses: must be an unquoted, exact checkout or upload pin")
      }
    }
    function classify_publisher_uses(value) {
      if (publisher_step_uses != "") {
        unsupported("a publish-report step declares more than one uses: action")
      } else if (value == checkout) {
        publisher_step_uses = "checkout"
      } else if (value == download) {
        publisher_step_uses = "download"
      } else {
        unsupported("publish-report uses: must be an unquoted, exact checkout or download pin")
      }
    }
    function finish_publisher_step() {
      if (!publisher_in_step) return
      if (publisher_step_uses == "checkout") publisher_checkouts++
      if (publisher_step_uses == "download") publisher_downloads++
      publisher_in_step = 0
      publisher_step_uses = ""
    }
    function start_discover_step(line) {
      finish_step()
      in_step = 1
      if (line ~ /^      - name: [A-Za-z0-9][A-Za-z0-9 ._-]*$/) {
        step_name = line
        sub(/^      - name: /, "", step_name)
      } else if (line == "      - uses: " checkout) {
        step_uses = "checkout"
      } else {
        unsupported("discover steps must use normal - name: or exact - uses: checkout syntax")
      }
    }
    function start_publisher_step(line) {
      finish_publisher_step()
      publisher_in_step = 1
      if (line !~ /^      - name: [A-Za-z0-9][A-Za-z0-9 ._-]*$/ && \
          line != "      - uses: " checkout && line != "      - uses: " download) {
        unsupported("publish-report steps must use normal - name: or exact pinned - uses: syntax")
      }
      if (line == "      - uses: " checkout) publisher_step_uses = "checkout"
      if (line == "      - uses: " download) publisher_step_uses = "download"
    }
    function noncomment_lower(line, trimmed) {
      trimmed = line
      sub(/^[[:space:]]*/, "", trimmed)
      if (trimmed ~ /^#/) return ""
      return tolower(line)
    }
    $0 == "on:" {
      on_count++
      in_on = 1
      next
    }
    in_on && /^[^[:space:]#]/ { in_on = 0 }
    in_on && /^  [^[:space:]#][^:]*:/ {
      trigger = $0
      sub(/^  /, "", trigger)
      sub(/:.*/, "", trigger)
      if (trigger == "workflow_dispatch" && $0 == "  workflow_dispatch:") {
        workflow_dispatches++
      } else {
        unsupported("on: may contain only the exact block trigger workflow_dispatch:")
      }
      next
    }
    $0 == "jobs:" {
      jobs_count++
      in_jobs = 1
      next
    }
    in_jobs && /^[^[:space:]#]/ {
      finish_step()
      finish_publisher_step()
      in_jobs = 0
      job = ""
    }
    in_jobs && /^  [^[:space:]#][^:]*:/ {
      finish_step()
      finish_publisher_step()
      if ($0 == "  discover:") {
        discover_jobs++
        job = "discover"
      } else if ($0 == "  publish-report:") {
        publisher_jobs++
        job = "publisher"
      } else {
        unsupported("only direct discover and publish-report jobs are supported")
        job = "unknown"
      }
      next
    }
    job == "discover" {
      if ($0 ~ /^    env:/) unsupported("job-level discover env: is forbidden")
      if ($0 ~ /^    [^[:space:]#][^:]*:/ && $0 !~ /^    (runs-on|permissions|steps):/) {
        unsupported("discover has an unsupported direct job property")
      }
      if ($0 ~ /^      - /) {
        start_discover_step($0)
        next
      }
      if (in_step && $0 ~ /^        .*env:/ && $0 !~ /^        env:/) {
        unsupported("discover env: uses a quoted or otherwise noncanonical key form")
      }
      if (in_step && $0 ~ /^        .*uses:/ && $0 !~ /^        uses:/) {
        unsupported("discover uses: uses a quoted or otherwise noncanonical key form")
      }
      if (in_step && $0 ~ /^        env:/ && $0 != "        env:") {
        unsupported("discover env: must use the normal block form")
      }
      if (in_step && $0 ~ /^        env:$/) next
      if (in_step && $0 ~ /^        uses:/) {
        value = $0
        sub(/^        uses: /, "", value)
        if ($0 != "        uses: " value || value ~ /["'\''{}\[\]]/) {
          unsupported("discover uses: has unsupported inline, quoted, or flow syntax")
        } else {
          classify_discover_uses(value)
        }
        next
      }
      if (in_step && $0 ~ /^        with:/) {
        if ($0 != "        with:" || (step_uses != "checkout" && step_uses != "upload")) {
          unsupported("only a discover checkout or upload action may use a normal with: block")
        } else {
          with_count++
          in_with = 1
        }
        next
      }
      if (in_step && in_with && /^        [^[:space:]#][^:]*:/) in_with = 0
      if (in_step && /^          persist-credentials:/) {
        if (step_uses != "checkout" || !in_with || $0 != "          persist-credentials: false") {
          bad_persist = 1
          unsupported("persist-credentials must be the exact false scalar in its checkout with: block")
        } else {
          persist_false_count++
        }
        next
      }
      line = noncomment_lower($0)
      if (in_step && line ~ /(gh_token|github_token|secrets[.]github_token)/) {
        if (step_name == "Prefetch triage input" && \
            $0 == "          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}") {
          # This is the sole approved GitHub-token construction in discover.
        } else {
          step_has_github_token = 1
        }
      }
      if (in_step && line ~ /opencode[[:space:]]+run/) {
        if ($0 == "          opencode run -m \"$MODEL\" --auto \"$PROMPT\"") {
          step_has_opencode = 1
        } else {
          unsupported("OpenCode must use the canonical block command form")
        }
      }
      next
    }
    job == "publisher" {
      line = noncomment_lower($0)
      if (line ~ /secrets[.]/ || line ~ /opencode/) {
        unsupported("publish-report may not reference secrets or OpenCode")
      }
      if ($0 ~ /^    if:/) {
        publisher_ifs++
        if ($0 != "    " publish_if) unsupported("publish-report has a noncanonical job-level if:")
        next
      }
      if ($0 ~ /^        if:/) unsupported("publish-report may not use step-level if:")
      if ($0 ~ /^    env:/ || $0 ~ /^        env:/) unsupported("publish-report may not define env:")
      if ($0 ~ /^        .*env:/ && $0 !~ /^        env:/) unsupported("publish-report env: uses a noncanonical key form")
      if ($0 ~ /^        .*uses:/ && $0 !~ /^        uses:/) unsupported("publish-report uses: uses a noncanonical key form")
      if ($0 ~ /^      - /) {
        start_publisher_step($0)
        next
      }
      if (publisher_in_step && $0 ~ /^        uses:/) {
        value = $0
        sub(/^        uses: /, "", value)
        if ($0 != "        uses: " value || value ~ /["'\''{}\[\]]/) {
          unsupported("publish-report uses: has unsupported inline, quoted, or flow syntax")
        } else {
          classify_publisher_uses(value)
        }
        next
      }
      next
    }
    END {
      finish_step()
      finish_publisher_step()
      if (on_count != 1 || workflow_dispatches != 1) unsupported("expected exactly one normal on:/workflow_dispatch: trigger block")
      if (jobs_count != 1 || discover_jobs != 1 || publisher_jobs != 1) unsupported("expected exactly one discover and one publish-report job")
      if (publisher_ifs != 1) unsupported("publish-report needs exactly one direct job-level manual if:")
      if (prefetch_steps != 1) unsupported("expected exactly one fixed Prefetch triage input step")
      if (discover_checkouts != 1 || discover_uploads != 1) unsupported("discover needs exactly one checkout and one upload action")
      if (opencode_steps != 1) unsupported("discover needs exactly one canonical OpenCode step")
      if (publisher_checkouts != 1 || publisher_downloads != 1) unsupported("publish-report needs exactly one checkout and one download action")
      exit invalid
    }
  ' "$WORKFLOW"
}

echo "=== OpenCode triage workflow safety ==="

if [ ! -f "$WORKFLOW" ]; then
  bad "workflow exists at .github/workflows/triage-opencode.yml"
else
  expect "workflow uses only the supported canonical triage form" check_canonical_workflow
  expect "all checkout occurrences are exact pinned normal literals" \
    check_pinned_occurrences 'actions/checkout' '11bd71901bbe5b1630ceea73d27597364c9af683' 2
  expect "all upload-artifact occurrences are exact pinned normal literals" \
    check_pinned_occurrences 'actions/upload-artifact' 'ea165f8d65b6e75b540449e92b4886f43607fa02' 1
  expect "all download-artifact occurrences are exact pinned normal literals" \
    check_pinned_occurrences 'actions/download-artifact' 'd3f86a106a0bac45b974a628896c90dbdf5c8093' 1
fi

if [ ! -f "$INIT" ]; then
  bad "init command exists for template-reference check"
elif rg -Fq 'templates/workflows/' "$INIT"; then
  bad "unsupported workflow form: init references a workflow template distribution path"
else
  ok "init does not reference any workflow template distribution path"
fi

if [ -d "$TEMPLATE_DIR" ] && find "$TEMPLATE_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print -quit | rg -q .; then
  bad "unsupported workflow form: a YAML workflow template is distributed from templates/workflows"
else
  ok "no YAML workflow template is distributed from templates/workflows"
fi

if [ "$fail" -ne 0 ]; then
  echo "triage-workflow-safety: FAILED ($fail failed, $pass passed)" >&2
  exit 1
fi

echo "triage-workflow-safety: PASS ($pass passed)"
