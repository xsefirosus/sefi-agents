#!/usr/bin/env bash
# validate-model-map.sh -- the model map is the single place a model identifier is written
# down, so this asserts nothing can silently fall out of it:
#   1. every agent declares a `tier:` in {high,mid,low}
#   2. every declared tier resolves to a model AND a reasoning effort for EVERY harness in
#      the map (a new harness or a new tier cannot leave a hole)
#   3. the literal `model:` in each agent equals what the map gives for claude-code at that
#      agent's tier -- the two fields coexist because the Claude Code plugin path has no
#      install step that could rewrite files, and two fields that can disagree will
#   4. every shell script parses (`bash -n`)
#
# On (3): Claude Code reads agents/*.md directly out of the plugin, so its model must be
# literally correct on disk. Every other harness gets rewritten at install time. That makes
# `model:` a derived value with a literal representation, and derived values drift unless
# something checks them.
#
# Also WARNS (never errors) when a harness maps two tiers to the same identifier: that
# collapses generator/evaluator separation to instructions-only. On a single-model harness
# it is an honest constraint, not a mistake, so it is not a build failure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
MAP="$CORE/config/model-map.yml"
MODEL_FOR="$CORE/scripts/model-for.sh"

errors=0
warns=0

[ -f "$MAP" ] || { echo "ERROR: $MAP not found"; exit 1; }

harnesses="$(awk '/^[a-z][a-z0-9-]*:[[:space:]]*$/ { k=$1; sub(/:$/,"",k); print k }' "$MAP")"
[ -n "$harnesses" ] || { echo "ERROR: model-map.yml declares no harnesses"; exit 1; }

agent_count=0
for f in "$CORE"/agents/*.md; do
  [ -e "$f" ] || continue
  agent_count=$((agent_count + 1))
  rel="plugins/sefi-core/agents/$(basename "$f")"
  fm="$(awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")"

  tier="$(printf '%s\n' "$fm" | sed -n 's/^tier:[[:space:]]*\([a-z]*\).*/\1/p' | head -1)"
  case "$tier" in
    high|mid|low) : ;;
    '') echo "ERROR: $rel - missing 'tier:' line (high|mid|low)"; errors=$((errors + 1)); continue ;;
    *)  echo "ERROR: $rel - tier '$tier' not in {high,mid,low}"; errors=$((errors + 1)); continue ;;
  esac

  # (2) the tier must resolve on every harness, not just the one someone tested -- model
  # AND reasoning effort, since a missing reasoning key silently drops the dial rather than
  # failing loudly.
  for h in $harnesses; do
    if ! bash "$MODEL_FOR" "$h" "$tier" >/dev/null 2>&1; then
      echo "ERROR: $rel - tier '$tier' has no model for harness '$h' in model-map.yml"
      errors=$((errors + 1))
    fi
    r="$(bash "$MODEL_FOR" "$h" "$tier" --reasoning 2>/dev/null || printf '')"
    case "$r" in
      none|minimal|low|medium|high|xhigh|max) : ;;
      '') echo "ERROR: $rel - tier '$tier' has no '${tier}_reasoning' for harness '$h'"
          errors=$((errors + 1)) ;;
      *)  echo "ERROR: $rel - tier '$tier' reasoning '$r' on '$h' is not a known effort level (none|minimal|low|medium|high|xhigh|max)"
          errors=$((errors + 1)) ;;
    esac
  done

  # (3) the literal Claude Code model must match the map.
  model="$(printf '%s\n' "$fm" | sed -n 's/^model:[[:space:]]*\([A-Za-z0-9._-]*\).*/\1/p' | head -1)"
  expected="$(bash "$MODEL_FOR" claude-code "$tier" 2>/dev/null || printf '')"
  if [ -n "$expected" ] && [ "$model" != "$expected" ]; then
    echo "ERROR: $rel - tier '$tier' maps to claude-code model '$expected', but the file says 'model: $model'"
    errors=$((errors + 1))
  fi
done

[ "$agent_count" -gt 0 ] || { echo "ERROR: no agent files found"; exit 1; }

# Generator/evaluator separation warning, per harness.
for h in $harnesses; do
  hi="$(bash "$MODEL_FOR" "$h" high 2>/dev/null || printf '')"
  mid="$(bash "$MODEL_FOR" "$h" mid 2>/dev/null || printf '')"
  if [ -n "$hi" ] && [ "$hi" = "$mid" ]; then
    echo "WARN: harness '$h' maps high and mid to the same model ('$hi') -- the qa-engineer judges the software-engineer on an identical model, so generator/evaluator separation is instructions-only there"
    warns=$((warns + 1))
  fi
done

# (4) Every shipped script must parse. Two live syntax errors during the 2026-08-11 batch
# came from an apostrophe inside an awk comment silently closing the shell single-quote
# around the awk program -- invisible on reading, instant under `bash -n`.
script_count=0
while IFS= read -r s; do
  script_count=$((script_count + 1))
  if ! bash -n "$s" 2>/dev/null; then
    echo "ERROR: ${s#"$ROOT"/} - shell syntax error (bash -n)"
    errors=$((errors + 1))
  fi
done < <(find "$ROOT/plugins" "$ROOT/adapters" -name '*.sh' 2>/dev/null; [ -f "$ROOT/install.sh" ] && echo "$ROOT/install.sh")

if [ "$errors" -ne 0 ]; then echo "validate-model-map: $errors error(s)"; exit 1; fi
echo "validate-model-map: OK ($agent_count agents, $(echo "$harnesses" | wc -w | tr -d ' ') harnesses, $script_count scripts parse; $warns warning(s))"
