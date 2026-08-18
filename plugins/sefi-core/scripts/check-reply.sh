#!/usr/bin/env bash
# check-reply.sh <agent-file> <reply-file>   (reply may be "-" for stdin)
#
# Deterministic gate on what a dispatched agent RETURNS -- the inbound counterpart to
# check-handoff.sh, which gates what a dispatch sends out. Plans have had
# validate-plan-structure.sh and handoffs have had check-handoff.sh; the reply itself was
# governed only by prose in each agent's `## Output contract`, and by
# `per_agent_return_tokens` in config/budget.yml, which no script had ever read.
#
# The failure it exists to prevent was observed live (2026-08-17): `prompt-engineer` --
# whose contract reads "Reply with exactly this digest and nothing else", which is the
# tightest wording in the roster -- returned a full HTML/CSS document, the deliverable of
# two other agents. Its tool whitelist HELD (it wrote no file); only content leaked. That
# is the gap: the whitelist governs file operations, nothing governed the reply.
#
# Checks, in order:
#   1. Declared labels. Derived from the agent's OWN `## Output contract` section, so the
#      contract stays the single source of truth (same principle as validate-doc-counts
#      deriving counts from disk rather than a hand-kept parallel table). A label is an
#      ALL-CAPS token plus colon at the START of a line or bullet. The anchor is
#      load-bearing: qa-engineer's contract says "If REJECT:" and "If PASS:" mid-line as
#      conditional branches, and ui-ux-designer's names per-mode branches, none of which
#      are simultaneously-required labels. Matching those would fail valid replies.
#   2. Verbosity. Word count against `per_agent_return_tokens` (hard cap, blocks and forces
#      a redo above it) and `per_agent_return_tokens_target` (soft target, 2026-08-18: a
#      NOTE only -- clearing target but staying within cap is not a failure). This is a WORD
#      count used as a PROXY for tokens -- a bound on verbosity, never an accounting claim.
#   3. Foreign deliverables, for READ-ONLY agents only (no Write/Edit/MultiEdit in their
#      tools line). Narrow, full-document markers only. A research digest may legitimately
#      quote code and technical-writer legitimately emits markdown, so "any fenced block"
#      would produce false failures -- and a gate that cries wolf on valid replies trains
#      its caller to ignore it, which is worse than no gate at all.
#
# KNOWN LIMITATION, documented rather than special-cased: an agent file with no parseable
# `tools:` line defaults to read-only for check 3 -- the safer direction against missing a
# real leak, but it means a write-capable agent's OWN legitimate output (e.g. HTML it just
# built) would be wrongly flagged if its `tools:` line were ever malformed. Not fixed
# because validate-agents.sh already requires every agent to declare `tools:` in CI, so
# this precondition has no live path to reach a CI-clean repo; adding a CANNOT-CHECK branch
# for a state CI already prevents would be speculative complexity, not a real fix.
#
# Exit codes (a caller must be able to tell these apart, per budget-check.sh's precedent):
#   0  clean -- every check that applies ran and passed
#   1  contract violated
#   2  usage error
#   3  CANNOT-CHECK -- no violation found, but the agent declares no parseable labels, so
#      the SHAPE check never ran. Distinct from 0 on purpose: reporting a pass for a check
#      that did not happen is the overclaim this repo's own gates exist to prevent.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="config/budget.yml"
AGENT=""
REPLY=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    --) shift ;;
    -)  # stdin marker for the reply, only valid in the reply position
        if [ -z "$AGENT" ]; then echo "check-reply: '-' is only valid as the reply argument" >&2; exit 2; fi
        REPLY="-"; shift ;;
    -*) echo "check-reply: unknown arg $1" >&2; exit 2 ;;
    *)
      if [ -z "$AGENT" ]; then AGENT="$1"
      elif [ -z "$REPLY" ]; then REPLY="$1"
      else echo "check-reply: unexpected arg $1" >&2; exit 2
      fi
      shift ;;
  esac
done

[ -n "$AGENT" ] && [ -n "$REPLY" ] \
  || { echo "check-reply: usage: check-reply.sh <agent-file> <reply-file>|-" >&2; exit 2; }
[ -f "$AGENT" ] || { echo "check-reply: agent file $AGENT not found" >&2; exit 2; }

if [ "$REPLY" = "-" ]; then
  REPLY_TXT="$(cat)"
else
  [ -f "$REPLY" ] || { echo "check-reply: reply file $REPLY not found" >&2; exit 2; }
  REPLY_TXT="$(cat "$REPLY")"
fi

# The cap is advisory-but-real: a missing config is a usage error, not a silent skip.
[ -f "$CONFIG" ] || CONFIG="$HERE/../../../config/budget.yml"
[ -f "$CONFIG" ] || { echo "check-reply: budget config not found (tried $CONFIG)" >&2; exit 2; }
CAP="$(sed -n 's/^per_agent_return_tokens:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONFIG" | head -1)"
[ -n "${CAP:-}" ] || { echo "check-reply: per_agent_return_tokens missing in $CONFIG" >&2; exit 2; }
# The target is advisory, not a gate: missing it degrades to no advisory note, never a
# usage error, since nothing depends on it to make a pass/fail call.
TARGET="$(sed -n 's/^per_agent_return_tokens_target:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONFIG" | head -1)"

errors=0
err() { echo "ERROR: $1"; errors=$((errors + 1)); }

AGENT_NAME="$(basename "$AGENT" .md)"

# --- 1. Declared labels, derived from the agent's own contract -------------------------
LABELS="$(awk '/^## Output contract/{p=1;next} /^## /{p=0} p' "$AGENT" \
  | grep -oE '^(- )?[A-Z][A-Z_]{2,}:' | sed 's/^- //' | sort -u)"

label_check_ran=0
if [ -n "$LABELS" ]; then
  label_check_ran=1
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    # Anchored the same way extraction is anchored: a real section start, not merely
    # mentioned. Live-observed gap, 2026-08-17: an unanchored match let "...I could not
    # form a SUGGESTED: route because..." pass as if SUGGESTED were a real section.
    printf '%s\n' "$REPLY_TXT" | grep -qE "^(- )?${label}" \
      || err "reply omits the declared label '$label' from $AGENT_NAME's output contract"
  done <<< "$LABELS"
fi

# --- 2. Verbosity against per_agent_return_tokens --------------------------------------
words="$(printf '%s' "$REPLY_TXT" | wc -w | tr -d ' ')"
if [ "${words:-0}" -gt "$CAP" ]; then
  err "reply is $words words against a $CAP per_agent_return_tokens cap (word count is a proxy for tokens, not a token count)"
elif [ -n "${TARGET:-}" ] && [ "${words:-0}" -gt "$TARGET" ]; then
  # Advisory only: does not touch $errors or the exit code. Aim for TARGET first; CAP is the
  # ceiling for when the job genuinely needs more (a verdict citing evidence), not the
  # default length to write toward.
  echo "NOTE: reply is $words words, over the $TARGET-word target but within the $CAP cap -- no action required" >&2
fi

# --- 3. Foreign deliverables, read-only agents only ------------------------------------
# Read-only means the agent cannot write files, so ANY full document in its reply is work
# that belongs to an agent which can. An agent that legitimately writes files is excluded:
# software-engineer quoting a diff is doing its job, not leaking someone else's.
tools_line="$(sed -n 's/^tools:[[:space:]]*//p' "$AGENT" | head -1)"
case "$tools_line" in
  *Write*|*Edit*|*MultiEdit*) read_only=0 ;;
  *) read_only=1 ;;
esac

if [ "$read_only" -eq 1 ]; then
  # Full-document markers hard to quote by accident: a single hit is real evidence.
  while IFS= read -r marker; do
    [ -z "$marker" ] && continue
    if printf '%s' "$REPLY_TXT" | grep -qiF "$marker"; then
      err "reply contains '$marker' -- a full deliverable belonging to an agent that can write files; $AGENT_NAME is read-only and must name the owning agent instead of producing it"
    fi
  done <<'MARKERS'
<!DOCTYPE
<html
MARKERS

  # Plan-skeleton headings: a single accurate quote of one heading (e.g. restating a
  # constraint verbatim from a referenced plan) is not evidence of a leaked plan -- only
  # correlated presence of several is. Live-observed false positive, 2026-08-17: a
  # single-marker check on "## Done Criteria" rejected an accurate verbatim quote. Fixed
  # to require >= 2 of the 6 headings validate-plan-structure.sh treats as one set.
  plan_hits=0
  for heading in "Objective" "Steps" "Files Touched" "Requires Tools" "Risks" "Done Criteria"; do
    printf '%s\n' "$REPLY_TXT" | grep -qE "^## $heading" && plan_hits=$((plan_hits + 1))
  done
  if [ "$plan_hits" -ge 2 ]; then
    err "reply contains $plan_hits of the 6 product-manager plan headings -- a full plan skeleton belonging to an agent that can write files; $AGENT_NAME is read-only and must name the owning agent instead of producing it"
  fi
fi

# --- verdict ---------------------------------------------------------------------------
if [ "$errors" -ne 0 ]; then
  echo "check-reply: $errors problem(s) -- reply rejected (agent=$AGENT_NAME)"
  exit 1
fi

if [ "$label_check_ran" -eq 0 ]; then
  echo "check-reply: CANNOT-CHECK shape for $AGENT_NAME -- its output contract declares no start-of-line ALL-CAPS labels, so only verbosity and foreign-deliverable checks ran (both passed, $words/$CAP words)" >&2
  exit 3
fi

echo "check-reply: OK (agent=$AGENT_NAME, $words/$CAP words, labels verified)" >&2
exit 0
