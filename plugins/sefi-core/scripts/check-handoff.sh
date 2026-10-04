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
#   output_schema: <OPTIONAL; path to a JSON Schema the returned labels must satisfy>
#   context: <inlined context; must stand alone>
#
# output_schema (optional, Stage 2) closes the gap where `writes:` names a directory
# but nothing states what the agent must put in it. A dispatch that promises a
# VERDICT: line and gets prose back satisfies every other check here and is still
# unusable to the reviewer. When the field is present the agent's own
# `## Output contract` declares the labels it emits; this gate checks that schema is
# readable, is real JSON, and names at least one required label -- then the
# dispatched reply is validated against it by check-reply.sh at return time.
#
# Deliberately NOT enforced here: that the reply matches. That is a return-time
# check, and check-handoff.sh runs BEFORE the agent exists. Enforcing it here would
# reject every dispatch. This gate only refuses to accept a schema it cannot read,
# which would otherwise fail silently at return time.
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
# Fields are deliberately confined to the envelope preamble. `context:` owns the remainder
# of the file, so a quoted example such as "agent: ..." in the context is not a duplicate
# authority field.
PREAMBLE="$(printf '%s\n' "$ENV_TXT" | sed '/^context:/,$d')"
field() { printf '%s\n' "$PREAMBLE" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }
err()   { echo "ERROR: $1"; errors=$((errors + 1)); }

for key in agent reads writes budget; do
  count="$(printf '%s\n' "$PREAMBLE" | grep -cE "^$key:")"
  [ "$count" -eq 1 ] || err "required field '$key:' must appear exactly once"
done
context_count="$(printf '%s\n' "$ENV_TXT" | grep -cE '^context:')"
[ "$context_count" -eq 1 ] || err "required field 'context:' must appear exactly once"

AGENT="$(field agent)"
READS="$(field reads)"
WRITES="$(field writes)"
BUDGET="$(field budget)"
CONTEXT="$(printf '%s\n' "$ENV_TXT" | sed -n '/^context:/,$p' | sed 's/^context:[[:space:]]*//')"

# 1. The pinned absolute output path. This is the load-bearing one: a relative path or a
# bare filename resolves against whatever working directory the dispatched agent happens to
# inherit, which is how work lands in $HOME and a verifier approves an empty folder.
case "$WRITES" in
  '') err "'writes:' is empty -- every dispatch names the absolute path it must write into" ;;
  /*|[A-Za-z]:[\\/]*) : ;;
  *) err "'writes: $WRITES' is not absolute -- a relative path resolves against the dispatched agent's inherited working directory, not yours" ;;
esac
normalized_writes="${WRITES//\\//}"
case "/$normalized_writes/" in
  */../*|*/./*) err "'writes:' must not contain traversal components" ;;
esac

# 2. The upstream file this dispatch consumes. "Everything the agent needs" starts with
# naming where it comes from.
[ -n "$READS" ] || err "'reads:' is empty -- name the specific upstream output file this dispatch consumes"
[ -n "$BUDGET" ] || err "'budget:' is empty -- name a checked scope or a non-negative USD amount"
printf '%s\n' "$BUDGET" | grep -qE '^(run|daily|dispatch|[0-9]+(\.[0-9]+)?)$' \
  || err "'budget:' must be run, daily, dispatch, or a non-negative USD amount"

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
printf '%s\n' "$AGENT" | grep -qE '^[a-z][a-z0-9-]*$' \
  || err "'agent:' must be a nonempty lowercase agent slug"
if [ -d "$AGENT_DIR" ]; then
  [ -f "$AGENT_DIR/$AGENT.md" ] \
    || err "'agent: $AGENT' does not resolve to $AGENT_DIR/$AGENT.md"
else
  err "agent directory unavailable: $AGENT_DIR"
fi

# 5. output_schema (optional). A declared-but-unreadable schema is worse than none:
# it reads as "structured output is checked" and then fails open at return time when
# nobody can read it. So presence is checked, and readability is checked, but the
# reply-vs-schema comparison is NOT -- that happens after the agent runs.
OSCHEMA="$(field output_schema)"
if [ -n "$OSCHEMA" ]; then
  schema_count="$(printf '%s\n' "$PREAMBLE" | grep -cE '^output_schema:')"
  [ "$schema_count" -eq 1 ] || err "'output_schema:' must appear at most once"
  case "$OSCHEMA" in
    /*|[A-Za-z]:[\\/]*) : ;;
    *) err "'output_schema: $OSCHEMA' is not absolute -- a relative schema path resolves against the dispatched agent's inherited working directory, not yours" ;;
  esac
  if [ ! -f "$OSCHEMA" ]; then
    err "'output_schema: $OSCHEMA' does not exist -- a schema that cannot be read fails open at return time, which is the case this check exists to prevent"
  elif ! command -v jq >/dev/null 2>&1; then
    # Fail closed on a missing dependency rather than skipping: a skipped check here
    # reads identically to a passed one.
    err "jq is required to validate 'output_schema:' but was not found"
  else
    # sefi-native-tool, not bare jq: on MSYS a native jq cannot open an MSYS path
    # (verified: `jq: error: Could not open file /c/...`), which would report every
    # schema as invalid JSON. The helper is a plain exec off MSYS, so this is
    # correct on POSIX CI too.
    JQ() { "$HERE/sefi-native-tool" jq "$@"; }
    if ! JQ -e . "$OSCHEMA" >/dev/null 2>&1; then
      err "'output_schema: $OSCHEMA' is not valid JSON"
    else
      # A schema with no required label constrains nothing, which is the silent-pass
      # this whole field exists to remove.
      required_n="$(JQ -r 'if (.required | type) == "array" then (.required | length) else 0 end' "$OSCHEMA" 2>/dev/null)"
      [ "${required_n:-0}" -gt 0 ] 2>/dev/null \
        || err "'output_schema: $OSCHEMA' declares no 'required' labels -- it constrains nothing, so the dispatch reads as structured while enforcing nothing"
    fi
  fi
fi

if [ "$errors" -ne 0 ]; then
  echo "check-handoff: $errors problem(s) -- dispatch blocked"
  exit 1
fi
echo "check-handoff: OK (agent=$AGENT writes=$WRITES)"
exit 0
