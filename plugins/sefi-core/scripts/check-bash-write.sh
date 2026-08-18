#!/usr/bin/env bash
# check-bash-write.sh -- PreToolUse hook (matcher: Bash), wired once in hooks/hooks.json.
# Blocks a write-shaped Bash command for whichever agent is CURRENTLY running, but only if
# that agent's OWN frontmatter already disallows Write, Edit, AND MultiEdit -- i.e. it
# already claims to never touch file content. An agent with real Write access is unaffected.
#
# Why hooks/hooks.json and not a per-agent frontmatter hook: Claude Code plugins do not
# support a `hooks:` field in an individual agent's own frontmatter -- "For security
# reasons, plugin subagents don't support the hooks ... frontmatter fields. These fields are
# ignored when loading agents from a plugin" (code.claude.com/docs/en/sub-agents.md,
# "Choose the subagent scope"; confirmed independently in plugins-reference.md's Agents
# section). A single hook registered here instead reads the standard PreToolUse payload's
# `agent_type` field (set whenever the hook fires inside a subagent) and looks up THAT
# agent's own agents/<agent_type>.md to decide whether to enforce -- one script, no
# per-agent wiring to keep in sync, and no plugin restriction to route around.
#
# Why this exists: live-confirmed (2026-08-18) via the engineering-manager's own forensic
# self-audit -- it queried its harness's session-log database and found itself had used
# Bash-invoked `Add-Content`/`sed -i` 8 times to write state-file content, directly
# violating its own `disallowedTools: Write, Edit, MultiEdit`. `disallowedTools` blocks the
# named tools; it does not and cannot see what a still-allowed `Bash` does.
#
# HONEST LIMIT, stated rather than overclaimed:
# - Pattern-matching on the literal command string, not a sandbox. Obfuscation (base64, an
#   uncommon interpreter not in the pattern list, a wrapper script) can still slip through.
# - Coverage depends on `agent_type` being set, which the docs describe as present "when the
#   session uses --agent or the hook fires inside a subagent". A Task-dispatched subagent
#   (how research-analyst/qa-engineer/security-engineer/support-engineer are always invoked,
#   and how engineering-manager is invoked when auto-routed or Task-dispatched) carries it.
#   A bare top-level session that merely follows engineering-manager's role text without
#   ever being dispatched as a real subagent -- an unusual, non-standard usage pattern here
#   -- would not, and this hook cannot see it.
# - Can false-positive: a Bash command with a literal `>` inside quotes (searching for `->`
#   or `=>` in code) reads as a redirect. When that happens, use the Grep/Glob tool instead
#   of Bash for the search -- every agent this hook can apply to already has both, and
#   neither is gated by this hook at all.
# - This narrows the gap; it does not close it. The only thing that fully closes it is not
#   granting Bash to an agent that must never write, which would remove its ability to run
#   tests, git, or search commands entirely -- judged a worse trade-off than a heuristic gate.
set -uo pipefail

INPUT="$(cat)"

json_tool() {
  local t
  for t in jq python3 python py; do
    if command -v "$t" >/dev/null 2>&1; then
      case "$t" in
        jq) printf '{}' | jq -e . >/dev/null 2>&1 || continue ;;
        *)  "$t" -c 'import json,sys' >/dev/null 2>&1 || continue ;;
      esac
      printf '%s' "$t"
      return 0
    fi
  done
  return 1
}

extract_command() {
  local t out=""
  t="$(json_tool)" || { printf ''; return 0; }
  if [ "$t" = jq ]; then
    out="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    printf '%s' "$out"; return 0
  fi
  out="$(printf '%s' "$INPUT" | "$t" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    sys.stdout.write(str(data.get("tool_input", {}).get("command", "")))
except Exception:
    pass
' 2>/dev/null || true)"
  printf '%s' "$out"
}

extract_agent_type() {
  local t out=""
  t="$(json_tool)" || { printf ''; return 0; }
  if [ "$t" = jq ]; then
    out="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
    printf '%s' "$out"; return 0
  fi
  out="$(printf '%s' "$INPUT" | "$t" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    sys.stdout.write(str(data.get("agent_type", "")))
except Exception:
    pass
' 2>/dev/null || true)"
  printf '%s' "$out"
}

# No WORKING JSON parser available, no agent_type, or no command: fail OPEN in every case. Blocking
# every Bash call on a host that lacks a working jq/python3/python/py would break every agent entirely --
# strictly worse than the gap this hook narrows. Not being able to identify which agent is
# running means this hook has nothing to scope enforcement to, so it does nothing rather
# than guess. Both are the same fail-open call check-reply.sh makes with its CANNOT-CHECK
# exit, stated here instead of silently assumed.
AGENT_TYPE="$(extract_agent_type)"
[ -z "$AGENT_TYPE" ] && exit 0

CMD="$(extract_command)"
[ -z "$CMD" ] && exit 0

# Only enforce for an agent whose OWN frontmatter already disallows Write, Edit, AND
# MultiEdit together -- i.e. one that already claims to never touch file content. An agent
# missing even one of the three has real write access through a sanctioned tool and this
# hook is not its concern.
AGENT_FILE="${CLAUDE_PLUGIN_ROOT:-}/agents/$AGENT_TYPE.md"
[ -f "$AGENT_FILE" ] || exit 0

DISALLOWED="$(sed -n 's/^disallowedTools:[[:space:]]*//p' "$AGENT_FILE" | head -1)"

has_disallowed_tool() {
  # has_disallowed_tool <tool-name> -- exact token match on DISALLOWED's comma-separated
  # list (avoids "Edit" false-matching inside "MultiEdit" via a plain substring check).
  printf '%s' "$DISALLOWED" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qxF "$1"
}

for t in Write Edit MultiEdit; do
  has_disallowed_tool "$t" || exit 0
done

REASON=""

has_token() {
  # has_token <cmd> <word> -- true if <word> starts a shell token in <cmd> (preceded by
  # start-of-string, ;, &, |, or whitespace), not merely present as a substring of a longer
  # word (so "tee" does not match "committee" or "fifteen").
  printf '%s' "$1" | grep -Eq "(^|[;&|[:space:]])$2"
}

if has_token "$CMD" 'sed' && has_token "$CMD" '\-i'; then
  REASON="sed -i (in-place file edit)"
elif printf '%s' "$CMD" | grep -qF -- '--in-place'; then
  REASON="sed --in-place"
elif has_token "$CMD" 'perl' && { has_token "$CMD" '\-i' || has_token "$CMD" '\-pi'; }; then
  REASON="perl -i (in-place file edit)"
elif has_token "$CMD" 'tee'; then
  REASON="tee (writes stdin to a file)"
elif printf '%s' "$CMD" | grep -qF 'of='; then
  REASON="dd of= (writes a file)"
elif printf '%s' "$CMD" | grep -qiE 'add-content|set-content|out-file'; then
  REASON="PowerShell content-write cmdlet"
elif printf '%s' "$CMD" | grep -qiE 'new-item.*-itemtype[[:space:]]+file'; then
  REASON="PowerShell New-Item -ItemType File"
elif printf '%s' "$CMD" | grep -qF '[System.IO.File]'; then
  REASON=".NET File I/O escape hatch"
elif printf '%s' "$CMD" | grep -qE '(python3?|node|ruby|perl)[[:space:]]+-[ce][[:space:]]' \
     && printf '%s' "$CMD" | grep -qE "open\([^)]*['\"][wa]['\"]|\\.write\(|writeFile|File\.write"; then
  REASON="inline interpreter (-c/-e) write API"
elif printf '%s' "$CMD" | grep -qE '^cp[[:space:]]|[;&|][[:space:]]*cp[[:space:]]' \
     || printf '%s' "$CMD" | grep -qE '^mv[[:space:]]|[;&|][[:space:]]*mv[[:space:]]'; then
  REASON="cp/mv (writes to a destination path)"
else
  SCRUBBED="$(printf '%s' "$CMD" | sed -E 's/[0-9]*>&[0-9]+//g; s/&>+[[:space:]]*\/dev\/null//g; s/[0-9]*>>?[[:space:]]*\/dev\/null//g')"
  case "$SCRUBBED" in
    *'>'*) REASON="shell redirection (> or >>) to a file" ;;
  esac
fi

if [ -n "$REASON" ]; then
  echo "check-bash-write: refusing a write-shaped Bash command from $AGENT_TYPE -- $REASON" >&2
  echo "$AGENT_TYPE's disallowedTools already says it never writes, edits, or multi-edits." >&2
  echo "If this is a false positive (e.g. a literal '>' inside a search pattern), use the" >&2
  echo "Grep/Glob tool instead of Bash -- neither is gated by this hook." >&2
  exit 2
fi

exit 0
