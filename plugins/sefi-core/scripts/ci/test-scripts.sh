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
echo "=== gen-router.sh (audit gap 5.1: trace notes evicting decisions) ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/memory/daily" "$TMP/memory/decisions"
printf -- '---\ntags: [index]\nmanaged-by: sefi-agents\n---\n# Memory Vault -- Router\n<!-- GENERATED:router -->\n<!-- /GENERATED:router -->\n' > "$TMP/memory/index.md"
printf -- '---\ntags: [daily]\nkeywords: alpha\n---\n' > "$TMP/memory/daily/2026-01-01.md"
printf -- '---\ntags: [decision]\nkeywords: zulu\n---\n' > "$TMP/memory/decisions/some-choice.md"

( cd "$TMP" && bash "$CORE/scripts/gen-router.sh" ) >/dev/null 2>&1

dec_line="$(grep -n 'decisions/some-choice' "$TMP/memory/index.md" | head -1 | cut -d: -f1)"
day_line="$(grep -n 'daily/2026-01-01' "$TMP/memory/index.md" | head -1 | cut -d: -f1)"
# Alphabetically "daily" sorts before "decisions", so a plain sort puts the trace note
# first and the injection's ~16-line window drops decisions entirely. Durability order
# must win over byte order.
if [ -n "$dec_line" ] && [ -n "$day_line" ] && [ "$dec_line" -lt "$day_line" ]; then
  ok "decisions/ precedes daily/ in the generated router"
else
  bad "decisions/ must precede daily/ (decisions at line ${dec_line:-none}, daily at line ${day_line:-none})"
fi

# The pre-existing drift check must not regress: a new note makes the router stale.
printf -- '---\ntags: [daily]\nkeywords: beta\n---\n' > "$TMP/memory/daily/2026-01-02.md"
expect_code 1 "--check flags drift after a new note is added" \
  bash -c "cd '$TMP' && bash '$CORE/scripts/gen-router.sh' --check"

echo
echo "=== install-opencode.sh (live bug, 2026-07-19: OpenCode hard-fails resolving a Claude Code model alias) ==="

# Live-observed: model: sonnet (a Claude Code tier alias) made OpenCode's own subagent
# dispatch fail hard with "Model not found: sonnet/" -- OpenCode tries to resolve the
# value as a real provider/model identifier and does not silently ignore it the way
# Claude Code treats "sonnet" as a native alias. Every one of this repo's 13 agents
# carries a model: line, so this broke every subagent dispatch on OpenCode, not one.
TMP_OC="$(mktemp -d)"
OPENCODE_HOME="$TMP_OC" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1
if grep -q '^model:' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  bad "install-opencode.sh must strip model: (OpenCode cannot resolve a bare Claude Code alias)"
else
  ok "install-opencode.sh strips model: from every converted agent"
fi
# Everything else must still survive byte-for-byte: pick one field per source line kind.
if grep -q '^disallowedTools: WebFetch, WebSearch$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null \
   && grep -q '^  edit: allow$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  ok "install-opencode.sh still converts tools/permission and keeps other fields intact"
else
  bad "install-opencode.sh regressed the tools/permission conversion or another frontmatter field"
fi
rm -rf "$TMP_OC"

echo
if [ "$fail" -ne 0 ]; then echo "test-scripts: $fail failed, $pass passed"; exit 1; fi
echo "test-scripts: OK ($pass passed)"
