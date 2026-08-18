#!/usr/bin/env bash
# validate-script-refs.sh -- catches the failure shape validate-links.sh cannot: that
# script proves a `scripts/x.sh` reference resolves on disk, in THIS repo checkout. It
# says nothing about whether a DISPATCHED AGENT can find that script at runtime, from an
# installed destination, following only the prose instruction. Found live: 24 agent/skill
# references told an LLM to "run scripts/x.sh" as a bare relative path with no stated
# resolution rule, while neither install.sh nor install-opencode.sh ever copied scripts/
# anywhere -- both facts validate-links.sh's own repo-tree walk was structurally blind to.
#
# The fix convention: every such reference is prefixed `${CLAUDE_PLUGIN_ROOT}/scripts/x.sh`
# -- inline-substituted by Claude Code's native plugin loader anywhere it appears in loaded
# agent/skill markdown (the same mechanism hooks/hooks.json already relies on), confirmed
# against official Claude Code docs rather than assumed. This validator enforces that every
# agent/skill `scripts/*.sh` mention actually carries that prefix -- a bare one is
# unresolvable by construction, the exact bug this exists to catch permanently.
#
# Exit codes: 0 clean, 1 one or more bare (unprefixed) references found, 2 usage/setup error.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT" || exit 2
CORE="plugins/sefi-core"

[ -d "$CORE/agents" ] && [ -d "$CORE/skills" ] || {
  echo "validate-script-refs: missing $CORE/agents or $CORE/skills" >&2
  exit 2
}

errors=0
scanned=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanned=$((scanned + 1))
  # A bare hit: "scripts/name.sh" occurring anywhere with no matching
  # "${CLAUDE_PLUGIN_ROOT}/scripts/name.sh" string elsewhere in the same file. grep -P
  # would make this a single lookbehind; POSIX/BSD grep portability (this repo targets
  # ubuntu CI and a human's local machine alike) rules that out, so it is a plain
  # substring check per distinct reference instead.
  while IFS= read -r bare; do
    [ -z "$bare" ] && continue
    if ! grep -qF "\${CLAUDE_PLUGIN_ROOT}/$bare" "$f"; then
      echo "ERROR: $f - bare reference '$bare' has no \${CLAUDE_PLUGIN_ROOT}/ prefix anywhere in the file"
      errors=$((errors + 1))
    fi
  done < <(grep -ohE 'scripts/[A-Za-z0-9_-]+\.sh' "$f" 2>/dev/null | sort -u)
done < <(git ls-files -- "$CORE/agents" "$CORE/skills" | grep -E '\.md$')

if [ "$errors" -ne 0 ]; then
  echo "validate-script-refs: $errors bare reference(s) -- unresolvable by a dispatched agent"
  exit 1
fi
echo "validate-script-refs: OK ($scanned files scanned, every scripts/*.sh reference carries \${CLAUDE_PLUGIN_ROOT}/)"
