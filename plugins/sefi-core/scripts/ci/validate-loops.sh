#!/usr/bin/env bash
# validate-loops.sh -- each *.loop.md declares all five moves + a human-checkpoint line,
# and the agentic-signals presence block (goal_intake, refusal_gate, verification,
# loop_discipline, close_out) so a prose-only "gate" that never refuses is caught.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DIR="$ROOT/plugins/sefi-core/templates/loops"

errors=0
count=0

for f in "$DIR"/*.loop.md; do
  [ -e "$f" ] || continue
  count=$((count + 1))
  rel="${f#"$ROOT"/}"

  # Move 1: Scheduling (the Trigger section is tagged SCHEDULING).
  grep -qE '(SCHEDULING|^## Trigger)' "$f" \
    || { echo "ERROR: $rel - missing move: Scheduling/Trigger"; errors=$((errors + 1)); }

  # Moves 2-5: Discovery, Handoff, Verification, Persistence.
  for m in Discovery Handoff Verification Persistence; do
    grep -q "$m" "$f" || { echo "ERROR: $rel - missing move: $m"; errors=$((errors + 1)); }
  done

  # Human checkpoint (six-element requirement).
  grep -qiE 'human checkpoint' "$f" \
    || { echo "ERROR: $rel - missing human checkpoint line"; errors=$((errors + 1)); }

  # Agentic-signals presence block.
  for sig in goal_intake refusal_gate verification loop_discipline close_out; do
    grep -q "$sig" "$f" || { echo "ERROR: $rel - missing agentic-signal: $sig"; errors=$((errors + 1)); }
  done
done

if [ "$count" -eq 0 ]; then echo "ERROR: no *.loop.md found in $DIR"; exit 1; fi
if [ "$errors" -ne 0 ]; then echo "validate-loops: $errors error(s)"; exit 1; fi
echo "validate-loops: OK ($count loop spec(s) validated)"
