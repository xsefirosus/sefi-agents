#!/usr/bin/env bash
# check-structure-diff.sh <before-file> <after-file>
#
# Deterministic structural-invariant diff between two versions of an agent or skill file --
# retro-improve's fast, instant pre-check, run BEFORE the qa-engineer's judgment call on a
# proposed edit (same ordering principle as check-bar.sh / check-reply.sh / gate.sh:
# deterministic checks first, spend the LLM judgment call second).
#
# This is NOT a port of the source proposal's SkillRegressionTester (stored input/expected-
# output pairs, diffed after running an executor_func). That shape does not map onto this
# repo: sefi-agents' agents are LLM-driven markdown prose, not deterministic functions, so
# there is no executor_func that reproduces byte-identical output for a stored input the
# way code does. What this checks instead: did the proposed edit silently strip or change a
# structural fact about the file -- a declared tool, the tier, the agentic-signals line, the
# anti-hallucination pointer -- the same shape validate-config-wired.sh catches for config
# keys, applied to agent/skill frontmatter instead.
#
# An ADDITION is never an error: agents legitimately gain fields over time (this exact repo
# added tier: and agentic-signals: to its whole roster mid-project). Only a field present
# BEFORE and absent or changed AFTER is flagged -- losing a capability silently is the
# actual regression shape; gaining one is not a regression at all.
#
# This does not replace retro-improve's ledger-based revert rule (state/retro-ledger.md):
# that rule is slow and statistical by design, needing 3-5 real qa-engineer verdicts
# accumulated over live dispatches after an edit ships. This is instant and deterministic,
# catching a structural regression before the edit is even committed. Neither replaces the
# other; if they ever start catching the identical failure shape, delete this one.
#
# Exit codes (a caller must be able to tell these apart, per budget-check.sh's precedent):
#   0  no removed or changed structural field
#   1  one or more structural fields removed or changed -- evidence for the qa-engineer
#   2  usage error
set -uo pipefail

BEFORE="${1:-}"
AFTER="${2:-}"
[ -n "$BEFORE" ] && [ -n "$AFTER" ] \
  || { echo "check-structure-diff: usage: check-structure-diff.sh <before-file> <after-file>" >&2; exit 2; }
[ -f "$BEFORE" ] || { echo "check-structure-diff: $BEFORE not found" >&2; exit 2; }
[ -f "$AFTER" ]  || { echo "check-structure-diff: $AFTER not found" >&2; exit 2; }

fingerprint() {
  # fingerprint <file> -- one KEY: value-shaped line per tracked structural fact.
  local f="$1" fm
  fm="$(awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")"

  # Every frontmatter key present, by name only -- catches a key vanishing entirely even
  # when its value is not individually tracked below.
  printf '%s\n' "$fm" | grep -oE '^[A-Za-z_-]+:' | sed 's/:$//' | sort -u \
    | while IFS= read -r k; do [ -n "$k" ] && echo "frontmatter-key: $k"; done

  local v
  v="$(printf '%s\n' "$fm" | sed -n 's/^tools:[[:space:]]*//p' | head -1)"
  [ -n "$v" ] && echo "tools: $v"
  v="$(printf '%s\n' "$fm" | sed -n 's/^disallowedTools:[[:space:]]*//p' | head -1)"
  [ -n "$v" ] && echo "disallowedTools: $v"
  v="$(printf '%s\n' "$fm" | sed -n 's/^tier:[[:space:]]*\([a-z]*\).*/\1/p' | head -1)"
  [ -n "$v" ] && echo "tier: $v"

  v="$(grep -m1 '^agentic-signals:' "$f" 2>/dev/null || true)"
  [ -n "$v" ] && echo "$v"

  grep -q "anti-hallucination" "$f" 2>/dev/null && echo "anti-hallucination-pointer: present"
}

BEFORE_FP="$(mktemp)"
AFTER_FP="$(mktemp)"
trap 'rm -f "$BEFORE_FP" "$AFTER_FP"' EXIT
fingerprint "$BEFORE" > "$BEFORE_FP"
fingerprint "$AFTER"  > "$AFTER_FP"

# A line present in BEFORE and absent from AFTER is removed-or-changed (a changed value is
# a removed old line plus an added new line under this comparison -- the removal half is
# what matters, and it is caught the same way either shape happens). A line present only in
# AFTER is an addition and is never flagged.
removed="$(comm -23 <(sort -u "$BEFORE_FP") <(sort -u "$AFTER_FP"))"

if [ -n "$removed" ]; then
  echo "check-structure-diff: structural field(s) removed or changed:" >&2
  printf '%s\n' "$removed" | sed 's/^/  - /' >&2
  echo "check-structure-diff: FLAGGED ($(printf '%s\n' "$removed" | grep -c .) field(s))" >&2
  exit 1
fi

echo "check-structure-diff: OK (no structural field removed or changed)" >&2
exit 0
