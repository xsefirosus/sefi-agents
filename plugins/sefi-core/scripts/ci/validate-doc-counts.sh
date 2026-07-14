#!/usr/bin/env bash
# validate-doc-counts.sh -- asserts the agent/skill/command counts quoted in README.md
# and plugins/sefi-core/README.md match the actual file counts on disk. Prose that claims
# a stale number fails the build instead of drifting silently.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

agents_n=$(find "$CORE/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
skills_n=$(find "$CORE/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
commands_n=$(find "$CORE/commands" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
loops_n=$(find "$CORE/templates/loops" -maxdepth 1 -name '*.loop.md' | wc -l | tr -d ' ')

errors=0

check() {
  # check <file> <label> <disk-count> <pattern>
  local file="$1" label="$2" disk="$3" pattern="$4"
  local rel="${file#"$ROOT"/}"
  while IFS= read -r claimed; do
    [ -z "$claimed" ] && continue
    if [ "$claimed" != "$disk" ]; then
      echo "ERROR: $rel - claims $claimed $label, disk has $disk"
      errors=$((errors + 1))
    fi
  done < <(grep -oE "$pattern" "$file" | grep -oE '[0-9]+')
}

check "$ROOT/README.md" "agents" "$agents_n" '\b[0-9]+ agents?\b'
check "$ROOT/README.md" "agent files" "$agents_n" '[0-9]+ agent files'
check "$ROOT/README.md" "SKILL.md" "$skills_n" '[0-9]+ SKILL\.md'
check "$ROOT/README.md" "loop spec" "$loops_n" '[0-9]+ loop spec'
check "$CORE/README.md" "agents" "$agents_n" '\b[0-9]+ agents\b'
check "$CORE/README.md" "skills" "$skills_n" '\b[0-9]+ skills\b'

if [ "$errors" -ne 0 ]; then echo "validate-doc-counts: $errors error(s)"; exit 1; fi
echo "validate-doc-counts: OK (agents=$agents_n skills=$skills_n commands=$commands_n loops=$loops_n, all prose matches disk)"
