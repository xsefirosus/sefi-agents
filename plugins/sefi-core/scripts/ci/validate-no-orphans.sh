#!/usr/bin/env bash
# validate-no-orphans.sh -- unwired-artifact linter. Every skills/*/references/ file is
# referenced from its SKILL.md; every templates/ file (except .gitkeep) is named in
# commands/init.md's copy list; every agents/*.md is listed in references/roster.md.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

errors=0

# 1. references files referenced from their skill's SKILL.md
while IFS= read -r ref; do
  skilldir="$(dirname "$(dirname "$ref")")"
  skillmd="$skilldir/SKILL.md"
  base="$(basename "$ref")"
  rel="${ref#"$ROOT"/}"
  if [ -f "$skillmd" ] && grep -qF "$base" "$skillmd"; then
    :
  else
    echo "ERROR: $rel - unreferenced (not named in $(basename "$skilldir")/SKILL.md)"
    errors=$((errors + 1))
  fi
done < <(find "$CORE/skills" -type f -path '*/references/*')

# 2. templates files named in commands/init.md (exclude .gitkeep)
INIT="$CORE/commands/init.md"
while IFS= read -r tf; do
  base="$(basename "$tf")"
  rel="${tf#"$ROOT"/}"
  if [ -f "$INIT" ] && grep -qF "$base" "$INIT"; then
    :
  else
    echo "ERROR: $rel - unreferenced (not in commands/init.md copy list)"
    errors=$((errors + 1))
  fi
done < <(find "$CORE/templates" -type f ! -name '.gitkeep')

# 3. agents listed in references/roster.md
ROSTER="$CORE/skills/sefi-orchestration/references/roster.md"
while IFS= read -r a; do
  base="$(basename "$a")"
  rel="${a#"$ROOT"/}"
  if [ -f "$ROSTER" ] && grep -qF "$base" "$ROSTER"; then
    :
  else
    echo "ERROR: $rel - not listed in references/roster.md"
    errors=$((errors + 1))
  fi
done < <(find "$CORE/agents" -name '*.md')

if [ "$errors" -ne 0 ]; then echo "validate-no-orphans: $errors error(s)"; exit 1; fi
echo "validate-no-orphans: OK (references, templates, agents all wired)"
