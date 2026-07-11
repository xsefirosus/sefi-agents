#!/usr/bin/env bash
# validate-skills.sh -- each SKILL.md non-empty; frontmatter has name + description;
# description is single-line (no YAML block scalar); body <= 300 lines.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DIR="$ROOT/plugins/sefi-core/skills"

errors=0
count=0

while IFS= read -r f; do
  count=$((count + 1))
  rel="${f#"$ROOT"/}"
  [ -s "$f" ] || { echo "ERROR: $rel - SKILL.md is empty"; errors=$((errors + 1)); continue; }

  fm="$(awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")"
  printf '%s\n' "$fm" | grep -q '^name:' \
    || { echo "ERROR: $rel - missing name"; errors=$((errors + 1)); }
  printf '%s\n' "$fm" | grep -q '^description:' \
    || { echo "ERROR: $rel - missing description"; errors=$((errors + 1)); }

  if printf '%s\n' "$fm" | grep -qE '^description:[[:space:]]*\|'; then
    echo "ERROR: $rel - description uses a YAML block scalar (must be single-line)"
    errors=$((errors + 1))
  fi

  lines="$(wc -l < "$f")"
  if [ "$lines" -gt 300 ]; then
    echo "ERROR: $rel - body $lines lines (max 300)"; errors=$((errors + 1))
  fi
done < <(find "$DIR" -name 'SKILL.md')

if [ "$count" -eq 0 ]; then echo "ERROR: no SKILL.md found in $DIR"; exit 1; fi
if [ "$errors" -ne 0 ]; then echo "validate-skills: $errors error(s)"; exit 1; fi
echo "validate-skills: OK ($count SKILL.md validated)"
