#!/usr/bin/env bash
# Contract coverage for the on-demand systems-audit skill and report lifecycle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
SKILL="$CORE/skills/systems-audit/SKILL.md"
METHOD="$CORE/skills/systems-audit/references/evidence-method.md"
REPORT_CONTRACT="$CORE/skills/systems-audit/references/report-contract.md"
AUDITOR="$CORE/agents/systems-auditor.md"
COMMAND="$CORE/commands/audit.md"
ROUTING="$CORE/skills/sefi-orchestration/references/routing-table.md"
fail=0

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; fail=$((fail + 1)); }
contains() { grep -Fq -- "$2" "$1" && ok "$3" || bad "$3"; }

echo '=== systems-audit skill ==='
[ -f "$SKILL" ] && ok 'skill exists' || bad 'skill exists'
[ -f "$METHOD" ] && ok 'evidence method exists' || bad 'evidence method exists'
if [ -f "$SKILL" ]; then
  desc="$(sed -n 's/^description:[[:space:]]*//p' "$SKILL" | head -1)"
  [ "$(printf '%s' "$desc" | wc -w | tr -d ' ')" -le 60 ] && ok 'skill description is within 60 words' || bad 'skill description is within 60 words'
  [ "$(wc -l < "$SKILL")" -le 300 ] && ok 'skill main file is within 300 lines' || bad 'skill main file is within 300 lines'
  contains "$SKILL" 'references/evidence-method.md' 'skill links the evidence method'
  contains "$SKILL" '../anti-hallucination/SKILL.md' 'skill points to anti-hallucination'
fi
if [ -f "$METHOD" ]; then
  for source in 'iso.org/standard/19011' 'csrc.nist.gov/pubs/sp/800/53/a/r5/final' 'theiia.org/en/standards/2024-standards' 'gao.gov/assets/d24106786.pdf'; do
    contains "$METHOD" "$source" "method links $source"
  done
  contains "$METHOD" 'PENDING' 'method distinguishes pending checks'
  contains "$METHOD" 'UNKNOWN' 'method distinguishes unsupported conclusions'
  contains "$METHOD" 'No certification claim' 'method disclaims certification'
fi

echo '=== routing and auditor contract ==='
contains "$ROUTING" 'explicit "Sefi department audit"' 'explicit Sefi department-audit intent routes to the auditor'
contains "$ROUTING" 'explicit skill invocation "systems-audit"' 'explicit skill invocation routes to the auditor'
contains "$AUDITOR" 'skills/systems-audit/SKILL.md' 'auditor points to the skill'
contains "$REPORT_CONTRACT" 'No findings in inspected surfaces.' 'clean reports use the required wording'
contains "$AUDITOR" 'STATUS: COMPLETE | STOPPED-TRIAGE | REFUSED-OVERWRITE | REFUSED-SCOPE | INCOMPLETE' 'auditor exposes incomplete status'
contains "$COMMAND" '--root <designated-project-root>' 'command requires explicit audit project root for report validation'
contains "$COMMAND" 'INCOMPLETE' 'command preserves incomplete audit status'

if [ "$fail" -ne 0 ]; then
  echo "test-systems-audit-contract: $fail failure(s)" >&2
  exit 1
fi
echo 'test-systems-audit-contract: OK'
