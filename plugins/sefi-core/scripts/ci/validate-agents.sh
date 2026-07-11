#!/usr/bin/env bash
# validate-agents.sh -- each agent frontmatter has name/description/tools/model/managed-by;
# model in {haiku,sonnet,opus}; description <= 2 sentences; description contains no ": "
# (colon+space breaks YAML plain-scalar parsing -- use " -- " instead); body carries the
# anti-hallucination pointer line (the canonical rule lives in skills/anti-hallucination).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DIR="$ROOT/plugins/sefi-core/agents"

errors=0
count=0

for f in "$DIR"/*.md; do
  [ -e "$f" ] || continue
  count=$((count + 1))
  rel="plugins/sefi-core/agents/$(basename "$f")"
  fm="$(awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")"

  for key in name description tools model managed-by; do
    printf '%s\n' "$fm" | grep -q "^$key:" \
      || { echo "ERROR: $rel - missing frontmatter key '$key'"; errors=$((errors + 1)); }
  done

  model="$(printf '%s\n' "$fm" | sed -n 's/^model:[[:space:]]*\([A-Za-z]*\).*/\1/p' | head -1)"
  case "$model" in
    haiku|sonnet|opus) : ;;
    *) echo "ERROR: $rel - model '$model' not in {haiku,sonnet,opus}"; errors=$((errors + 1)) ;;
  esac

  mb="$(printf '%s\n' "$fm" | sed -n 's/^managed-by:[[:space:]]*//p' | head -1)"
  [ "$mb" = "sefi-agents" ] \
    || { echo "ERROR: $rel - managed-by must be 'sefi-agents' (got '$mb')"; errors=$((errors + 1)); }

  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  sentences="$(printf '%s' "$desc" | grep -oE '[.!?]' | wc -l | tr -d ' ')"
  if [ "${sentences:-0}" -gt 2 ]; then
    echo "ERROR: $rel - description has $sentences sentences (max 2)"; errors=$((errors + 1))
  fi

  if printf '%s' "$desc" | grep -qE ': '; then
    echo "ERROR: $rel - description contains ': ' (colon+space), which breaks YAML plain-scalar parsing; use ' -- ' instead"
    errors=$((errors + 1))
  fi

  grep -q 'anti-hallucination' "$f" \
    || { echo "ERROR: $rel - missing anti-hallucination pointer line"; errors=$((errors + 1)); }
done

if [ "$count" -eq 0 ]; then echo "ERROR: no agent files found in $DIR"; exit 1; fi
if [ "$errors" -ne 0 ]; then echo "validate-agents: $errors error(s)"; exit 1; fi
echo "validate-agents: OK ($count agent files validated)"
