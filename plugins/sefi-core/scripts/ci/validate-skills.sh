#!/usr/bin/env bash
# validate-skills.sh -- each SKILL.md non-empty; frontmatter has name + description;
# description is single-line (no YAML block scalar) and contains no ": " (colon+space
# breaks YAML plain-scalar parsing -- use " -- " instead); body <= 300 lines; body
# carries the anti-hallucination pointer line (the canonical rule lives in
# skills/anti-hallucination).
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

  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  if printf '%s' "$desc" | grep -qE ': '; then
    echo "ERROR: $rel - description contains ': ' (colon+space), which breaks YAML plain-scalar parsing; use ' -- ' instead"
    errors=$((errors + 1))
  fi

  lines="$(wc -l < "$f")"
  if [ "$lines" -gt 300 ]; then
    echo "ERROR: $rel - body $lines lines (max 300)"; errors=$((errors + 1))
  fi

  grep -q 'anti-hallucination' "$f" \
    || { echo "ERROR: $rel - missing anti-hallucination pointer line"; errors=$((errors + 1)); }
done < <(find "$DIR" -name 'SKILL.md')

if [ "$count" -eq 0 ]; then echo "ERROR: no SKILL.md found in $DIR"; exit 1; fi
if [ "$errors" -ne 0 ]; then echo "validate-skills: $errors error(s)"; exit 1; fi
echo "validate-skills: OK ($count SKILL.md validated)"
