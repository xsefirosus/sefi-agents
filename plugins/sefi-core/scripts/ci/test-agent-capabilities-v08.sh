#!/usr/bin/env bash
# Offline v0.8 source contract test. It checks literal capabilities in the managed agent
# and routing sources, then delegates frontmatter validation to validate-agents.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/agent-capabilities-v08"
MANIFEST="$FIXTURES/required-lines.txt"
SOURCES="$FIXTURES/expected-agent-sources.txt"
errors=0

bad() {
  echo "ERROR: $*" >&2
  errors=$((errors + 1))
}

[ -f "$MANIFEST" ] || bad "missing fixture $MANIFEST"
[ -f "$SOURCES" ] || bad "missing fixture $SOURCES"

if [ -f "$MANIFEST" ]; then
  while IFS= read -r row || [ -n "$row" ]; do
    case "$row" in ""|\#*) continue ;; esac
    rel="${row%%:::*}"
    needle="${row#*:::}"
    if [ "$rel" = "$needle" ]; then
      bad "malformed fixture row: $row"
      continue
    fi
    target="$ROOT/$rel"
    if [ ! -f "$target" ]; then
      bad "missing required source: $rel"
    elif ! grep -Fq -- "$needle" "$target"; then
      bad "$rel missing required text: $needle"
    fi
  done < "$MANIFEST"
fi

if [ -e "$CORE/agents/knowledge-manager.md" ]; then
  bad "managed legacy agent source knowledge-manager.md still exists"
fi

if [ -f "$SOURCES" ]; then
  while IFS= read -r agent || [ -n "$agent" ]; do
    case "$agent" in ""|\#*) continue ;; esac
    source="$CORE/agents/$agent.md"
    if [ ! -f "$source" ]; then
      bad "missing managed agent source: $agent.md"
    elif ! grep -qx "name: $agent" "$source"; then
      bad "$agent.md has no matching name frontmatter"
    fi
  done < "$SOURCES"
fi

if ! bash "$CORE/scripts/ci/validate-agents.sh"; then
  bad "validate-agents.sh rejected agent sources"
fi

if [ "$errors" -ne 0 ]; then
  echo "test-agent-capabilities-v08: $errors error(s)" >&2
  exit 1
fi
echo "test-agent-capabilities-v08: OK (offline rules and agent sources validated)"
