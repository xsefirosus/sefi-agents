#!/usr/bin/env bash
# Offline source-contract checks for the v0.9.1 Cartographer protocol.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
AGENT="$CORE/agents/research-codebase-cartographer.md"
COMMAND="$CORE/commands/map-codebase.md"
CONTRACT="$CORE/skills/sefi-orchestration/references/cartographer-v091.md"
fail=0

need_file() { [ -f "$1" ] || { echo "FAIL: missing $1" >&2; fail=1; }; }
need() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "$file" || { echo "FAIL: $file lacks: $text" >&2; fail=1; }
}

need_file "$AGENT"
need_file "$COMMAND"
need_file "$CONTRACT"

for text in \
  'sefi-codebase-map/v2' \
  'MAP|TRACE|IMPACT|DELTA|VISUALIZE|CONTEXT' \
  '--base <git-ref>' \
  '--budget <estimated-tokens>' \
  'context_packet_budget: 24000' \
  '4,000 and 64,000' \
  'state/codebase-map-<slug>.json' \
  '.sefi/cartographer/<slug>/'; do
  need "$COMMAND" "$text"
done

for text in \
  'source evidence contract' \
  'worktree_id' \
  'same, behind, ahead, diverged, or unknown' \
  'content_hash' \
  'structural_hash' \
  'content-only' \
  'symbol-loss gate' \
  'candidate-map.json' \
  'incremental-diagnostics.json' \
  'ready, pending, stale, or missing' \
  'unresolved.json' \
  'callback, event, interface-dispatch, reflection, framework-runtime, or unknown' \
  'IMPACT predicts possible effects before implementation' \
  'DELTA reports actual changes after implementation' \
  'estimated tokens = ceiling(UTF-8 byte count / 2)' \
  'full, structural, directory-only, or excluded' \
  'private-key blocks' \
  '[REDACTED:credential]' \
  'Graft' \
  'CodeGraph' \
  'Never install or initialize CodeGraph' \
  'viewer.html' \
  'no server, dependency, or network'; do
  need "$CONTRACT" "$text"
done

for text in \
  'cartographer-v091.md' \
  'read-only access to target source' \
  'SHA-256 hash of selected source text' \
  'requested offline viewer regardless of graph size' \
  'needs-attention' \
  'CONTEX' \
  'source evidence'; do
  need "$AGENT" "$text"
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo 'test-cartographer-v091: PASS'
