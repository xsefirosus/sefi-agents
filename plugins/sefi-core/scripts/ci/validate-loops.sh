#!/usr/bin/env bash
# validate-loops.sh -- each *.loop.md declares all five moves + a human-checkpoint line,
# and the agentic-signals presence block (goal_intake, refusal_gate, verification,
# loop_discipline, close_out) so a prose-only "gate" that never refuses is caught.
#
# Move detection is anchored to the `## <Move>` HEADING, not a bare substring. An
# unanchored `grep -q Discovery` is satisfied by the word appearing anywhere -- including
# inside a sentence in another section -- so a loop spec missing the section entirely
# passed this validator, which is exactly the guarantee it exists to make (2026-08-11
# audit). Anchoring is the difference between "the file mentions discovery" and "the file
# HAS a Discovery move".
#
# Both the shipped templates and the project's own loops/ are validated: a broken spec is a
# real defect wherever it lives, and this repo dogfoods its own loops at the root.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TPL_DIR="$ROOT/plugins/sefi-core/templates/loops"
PROJ_DIR="$ROOT/loops"

errors=0
tpl_count=0
proj_count=0

check_loop() {
  local f="$1" rel="${1#"$ROOT"/}"

  # Move 1: Scheduling (the Trigger section is tagged SCHEDULING).
  grep -qE '^## Trigger|^## .*SCHEDULING' "$f" \
    || { echo "ERROR: $rel - missing move: Scheduling/Trigger"; errors=$((errors + 1)); }

  # Moves 2-5: Discovery, Handoff, Verification, Persistence -- each as its own heading.
  for m in Discovery Handoff Verification Persistence; do
    grep -qE "^## $m" "$f" \
      || { echo "ERROR: $rel - missing move: $m (no '## $m' heading)"; errors=$((errors + 1)); }
  done

  # Human checkpoint (six-element requirement).
  grep -qiE '^## Human checkpoint' "$f" \
    || { echo "ERROR: $rel - missing human checkpoint section"; errors=$((errors + 1)); }

  # Agentic-signals presence block.
  for sig in goal_intake refusal_gate verification loop_discipline close_out; do
    grep -q "$sig" "$f" || { echo "ERROR: $rel - missing agentic-signal: $sig"; errors=$((errors + 1)); }
  done

  # requires-tools: the external commands this loop's moves depend on, probed by
  # scripts/probe-tools.sh before the loop runs. Required, not optional: an undeclared
  # dependency is exactly how a loop discovers mid-cycle that it cannot do its job (this
  # repo's own first live triage lost two of six findings to a missing gh CLI). A loop with
  # no external dependencies declares `requires-tools: none` and says so deliberately.
  grep -qE '^requires-tools:[[:space:]]*[^[:space:]]' "$f" \
    || { echo "ERROR: $rel - missing 'requires-tools:' line (use 'none' if it truly needs no external command)"; errors=$((errors + 1)); }
}

for f in "$TPL_DIR"/*.loop.md; do
  [ -e "$f" ] || continue
  tpl_count=$((tpl_count + 1))
  check_loop "$f"
done

for f in "$PROJ_DIR"/*.loop.md; do
  [ -e "$f" ] || continue
  proj_count=$((proj_count + 1))
  check_loop "$f"
done

if [ "$tpl_count" -eq 0 ]; then echo "ERROR: no *.loop.md found in $TPL_DIR"; exit 1; fi
if [ "$errors" -ne 0 ]; then echo "validate-loops: $errors error(s)"; exit 1; fi
echo "validate-loops: OK ($tpl_count loop spec(s) validated, plus $proj_count in this project's loops/)"
