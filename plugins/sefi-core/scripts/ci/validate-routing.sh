#!/usr/bin/env bash
# validate-routing.sh -- deterministic consistency check on the routing table. Verifies
# every agent named in routing-table.md exists as an agents/*.md file, that each fixture
# trigger resolves to its expected agent in exactly one row, and that no trigger row is
# duplicated. NOT a dispatch test: it cannot check whether an LLM routes correctly at
# runtime, only that the table it reads is internally consistent and its agents exist.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
TABLE="$CORE/skills/sefi-orchestration/references/routing-table.md"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/routing-cases.txt"

errors=0

# 1. Every "Default agent" named in a table row exists as an agent file, unless it is a
#    known non-file placeholder (per loop spec).
while IFS= read -r agent; do
  [ -z "$agent" ] && continue
  case "$agent" in
    *"per loop spec"*) continue ;;  # documented placeholder, not an agent file
    "Default agent"|---*) continue ;;
  esac
  if [ ! -f "$CORE/agents/$agent.md" ]; then
    echo "ERROR: routing-table names agent '$agent' with no agents/$agent.md"
    errors=$((errors + 1))
  fi
done < <(awk -F'|' '/^\|/{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}' "$TABLE" | sort -u)

# 2. Each fixture trigger appears in exactly one row, and that row names the expected agent.
while IFS='|' read -r trig expected; do
  [ -z "$trig" ] && continue
  matches="$(grep -c -- "$trig" "$TABLE")"
  if [ "$matches" -ne 1 ]; then
    echo "ERROR: fixture trigger '$trig' matches $matches rows (expected exactly 1)"
    errors=$((errors + 1))
    continue
  fi
  row="$(grep -- "$trig" "$TABLE")"
  if ! printf '%s' "$row" | grep -qF "$expected"; then
    echo "ERROR: fixture '$trig' expected agent '$expected' but its row does not name it"
    errors=$((errors + 1))
  fi
done < "$FIXTURES"

# 3. No duplicate trigger cells (same first column twice).
dupes="$(awk -F'|' '/^\|/{gsub(/^[ \t]+|[ \t]+$/,"",$2); if($2!="" && $2 !~ /^-+$/ && $2!="Trigger") print $2}' "$TABLE" | sort | uniq -d)"
if [ -n "$dupes" ]; then
  echo "ERROR: duplicate trigger rows: $dupes"
  errors=$((errors + 1))
fi

if [ "$errors" -ne 0 ]; then echo "validate-routing: $errors error(s)"; exit 1; fi
echo "validate-routing: OK (routing-table agents exist, fixtures resolve, no duplicate triggers)"
