#!/usr/bin/env bash
# validate-token-budget.sh -- repo bloat linter. Fail if any description > 60 words; any
# agent file > 150 lines; any SKILL.md > 300 lines; templates/memory/index.md > 60 lines;
# or total agents/ word count > agent_count x 640 (the original cap was 4500 for 7 agents,
# ~643 words per agent; the per-agent budget scales with the roster).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

errors=0

read_desc() {
  awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$1" \
    | sed -n 's/^description:[[:space:]]*//p' | head -1
}

check_desc() {
  local f="$1" rel="$2" desc w
  desc="$(read_desc "$f")"
  [ -z "$desc" ] && return 0
  w="$(printf '%s' "$desc" | wc -w | tr -d ' ')"
  if [ "$w" -gt 60 ]; then
    echo "ERROR: $rel - description $w words (max 60)"; errors=$((errors + 1))
  fi
}

# Agent files: <= 150 lines each; total words <= count x 640; descriptions <= 60 words.
agent_words=0
agent_count=0
for f in "$CORE"/agents/*.md; do
  [ -e "$f" ] || continue
  agent_count=$((agent_count + 1))
  rel="plugins/sefi-core/agents/$(basename "$f")"
  lines="$(wc -l < "$f")"
  [ "$lines" -gt 150 ] && { echo "ERROR: $rel - $lines lines (max 150)"; errors=$((errors + 1)); }
  w="$(wc -w < "$f")"; agent_words=$((agent_words + w))
  check_desc "$f" "$rel"
done
agent_cap=$((agent_count * 640))
if [ "$agent_words" -gt "$agent_cap" ]; then
  echo "ERROR: plugins/sefi-core/agents - total $agent_words words (max $agent_cap for $agent_count agents)"; errors=$((errors + 1))
fi

# SKILL.md: <= 300 lines each; descriptions <= 60 words.
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  lines="$(wc -l < "$f")"
  [ "$lines" -gt 300 ] && { echo "ERROR: $rel - $lines lines (max 300)"; errors=$((errors + 1)); }
  check_desc "$f" "$rel"
done < <(find "$CORE/skills" -name 'SKILL.md')

# Memory index template: <= 60 lines.
IDX="$CORE/templates/memory/index.md"
if [ -f "$IDX" ]; then
  lines="$(wc -l < "$IDX")"
  [ "$lines" -gt 60 ] && { echo "ERROR: plugins/sefi-core/templates/memory/index.md - $lines lines (max 60)"; errors=$((errors + 1)); }
fi

if [ "$errors" -ne 0 ]; then echo "validate-token-budget: $errors error(s)"; exit 1; fi
echo "validate-token-budget: OK (all within token budgets; agents total $agent_words words)"
