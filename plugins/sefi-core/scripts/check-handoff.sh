#!/usr/bin/env bash
# check-handoff.sh <envelope-file>   (or: ... | check-handoff.sh -)
#
# Deterministic gate on a dispatch envelope, the counterpart to
# validate-plan-structure.sh. Plans have had a structural gate for a while; handoffs --
# which fail more expensively -- had only prose in sefi-orchestration/SKILL.md and the
# engineering-manager's protocol. This closes that asymmetry.
#
# The failure it exists to prevent was observed live in a predecessor system and is
# recorded in qa-engineer.md item 4: a dispatched task with no pinned absolute output path
# wrote to the user's home directory, and the reviewer reading the designated folder
# approved an empty one. Nothing downstream catches that -- an empty folder and a folder
# whose work was never written are byte-identical to a verifier.
#
# Envelope format (one field per line, `key: value`; `context:` may run to end of file):
#   agent:   <agent slug, e.g. software-engineer>
#   reads:   <upstream output path(s) this dispatch consumes, comma-separated>
#   writes:  <ABSOLUTE path the dispatched agent must write into>
#   budget:  <scope or usd figure checked before dispatch>
#   context: <inlined context; must stand alone>
#
# Exit 0 when the envelope is well-formed; 1 when it is not; 2 on a usage error.
set -uo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "check-handoff: usage: check-handoff.sh <envelope-file>|-" >&2; exit 2; }

if [ "$SRC" = "-" ]; then
  ENV_TXT="$(cat)"
else
  [ -f "$SRC" ] || { echo "check-handoff: $SRC not found" >&2; exit 2; }
  ENV_TXT="$(cat "$SRC")"
fi

errors=0
field() { printf '%s\n' "$ENV_TXT" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }
err()   { echo "ERROR: $1"; errors=$((errors + 1)); }

for key in agent reads writes budget context; do
  printf '%s\n' "$ENV_TXT" | grep -qE "^$key:" || err "missing required field '$key:'"
done

AGENT="$(field agent)"
READS="$(field reads)"
WRITES="$(field writes)"
CONTEXT="$(printf '%s\n' "$ENV_TXT" | sed -n '/^context:/,$p' | sed 's/^context:[[:space:]]*//')"

# 1. The pinned absolute output path. This is the load-bearing one: a relative path or a
# bare filename resolves against whatever working directory the dispatched agent happens to
# inherit, which is how work lands in $HOME and a verifier approves an empty folder.
case "$WRITES" in
  '') err "'writes:' is empty -- every dispatch names the absolute path it must write into" ;;
  /*|[A-Za-z]:[\\/]*) : ;;
  *) err "'writes: $WRITES' is not absolute -- a relative path resolves against the dispatched agent's inherited working directory, not yours" ;;
esac

# 2. The upstream file this dispatch consumes. "Everything the agent needs" starts with
# naming where it comes from.
[ -n "$READS" ] || err "'reads:' is empty -- name the specific upstream output file this dispatch consumes"

# 3. Self-contained context. The handoff rule's whole point: the next agent does not share
# your context window, so a back-reference resolves to nothing on its side.
if [ -z "$(printf '%s' "$CONTEXT" | tr -d '[:space:]')" ]; then
  err "'context:' is empty -- inline what the dispatched agent needs; it does not share your context window"
else
  while IFS= read -r phrase; do
    [ -z "$phrase" ] && continue
    if printf '%s' "$CONTEXT" | grep -qiF "$phrase"; then
      err "context contains a dangling back-reference ('$phrase') -- inline the content instead"
    fi
  done <<'PHRASES'
as discussed above
as described above
as mentioned above
see above
per the above
the previous message
as noted earlier
as stated earlier
described earlier
PHRASES
fi

# 4. The agent must exist. A typo'd slug routes nowhere and surfaces as a mysterious
# no-op rather than a routing error.
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$HERE/../agents"
if [ -n "$AGENT" ] && [ -d "$AGENT_DIR" ]; then
  [ -f "$AGENT_DIR/$AGENT.md" ] \
    || err "'agent: $AGENT' does not resolve to $AGENT_DIR/$AGENT.md"
fi

if [ "$errors" -ne 0 ]; then
  echo "check-handoff: $errors problem(s) -- dispatch blocked"
  exit 1
fi
echo "check-handoff: OK (agent=$AGENT writes=$WRITES)"
exit 0
