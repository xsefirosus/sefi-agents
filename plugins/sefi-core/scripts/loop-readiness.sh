#!/usr/bin/env bash
# loop-readiness.sh -- prints a 0-100 readiness score per loops/*.loop.md in the current
# project (never the plugin's own templates/). Advisory only: never exits nonzero, never
# gates a build. Score is five signals x 20 points; see docs/LOOPS.md for the L0-L3
# mapping. No score authorizes skipping the human checkpoint --
# skills/sefi-orchestration/references/human-checkpoint.md.
set -uo pipefail

DIR="loops"
METRICS="state/metrics.md"

[ -d "$DIR" ] || { echo "loop-readiness: no $DIR/ directory (run /sefi:init first)" >&2; exit 1; }

for f in "$DIR"/*.loop.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .loop.md)"
  score=0

  # 1. Five moves present.
  moves_ok=1
  for m in Discovery Handoff Verification Persistence; do
    grep -q "$m" "$f" || moves_ok=0
  done
  grep -qE '(SCHEDULING|^## Trigger)' "$f" || moves_ok=0
  [ "$moves_ok" -eq 1 ] && score=$((score + 20))

  # 2. All five agentic-signals present.
  sig_ok=1
  for sig in goal_intake refusal_gate verification loop_discipline close_out; do
    grep -q "$sig" "$f" || sig_ok=0
  done
  [ "$sig_ok" -eq 1 ] && score=$((score + 20))

  # 3. Human checkpoint line present.
  grep -qiE 'human checkpoint' "$f" && score=$((score + 20))

  # 4. Budget section has real values, not unfilled placeholders (a bare "<" marks one).
  # Scoped to the Budget section body only -- an unrelated placeholder elsewhere in the
  # file (e.g. a branch-naming `<slug>` in Handoff) must not count against this check.
  budget_body="$(awk '/^## Budget/{p=1;next} /^## /{p=0} p' "$f")"
  if echo "$budget_body" | grep -qE '\$[0-9]' && ! echo "$budget_body" | grep -qE '<[a-zA-Z]'; then
    score=$((score + 20))
  fi

  # 5. Proof of activity: at least one real state/metrics.md row naming this loop.
  if [ -f "$METRICS" ] && grep -q "$name" "$METRICS"; then
    score=$((score + 20))
  fi

  if [ "$score" -lt 40 ]; then level="L0 Draft"
  elif [ "$score" -lt 60 ]; then level="L1 Documented"
  elif [ "$score" -lt 80 ]; then level="L2 Wired"
  else level="L3 Proven"
  fi

  echo "$name: $score/100 ($level)"
done
