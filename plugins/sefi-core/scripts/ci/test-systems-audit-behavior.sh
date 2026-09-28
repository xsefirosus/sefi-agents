#!/usr/bin/env bash
# Deterministic contract coverage. This validates report and routing inputs, not LLM dispatch behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
VALIDATOR="$CORE/scripts/ci/validate-audit-report.sh"
PATH_GUARD="$CORE/scripts/ci/prepare-audit-report-path.sh"
FINDING_FORMATTER="$CORE/scripts/ci/format-audit-findings.sh"
REPORT_CONTRACT="$CORE/skills/systems-audit/references/report-contract.md"
FIXTURES="$CORE/scripts/ci/fixtures/routing-cases.txt"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-systems-audit-behavior.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; fail=$((fail + 1)); }

write_report() {
  local path="$1" scope="$2" status="$3" counts="$4" findings="$5"
  cat > "$path" <<EOF
## Summary
Scope: $scope
Status: $status
Severity counts: $counts
## Scope
Scope: $scope
## Method
Evidence was inspected within the designated project root.
## Findings
$findings
## Fixes
No fixes are planned without explicit confirmation.
## Improvements
None.
## Nice-to-haves
None.
## Follow-up
Ask whether to plan fixes, then stop.
EOF
}

echo '=== report contract and installed validator ==='
[ -f "$REPORT_CONTRACT" ] && ok 'canonical report contract exists' || bad 'canonical report contract exists'
if [ -f "$REPORT_CONTRACT" ]; then
  for heading in Summary Scope Method Findings Fixes Improvements Nice-to-haves Follow-up; do
    grep -qxF "## $heading" "$REPORT_CONTRACT" && ok "report contract has ## $heading" || bad "report contract has ## $heading"
  done
  grep -Fq 'runtime root' "$REPORT_CONTRACT" && ok 'report contract resolves validator from runtime root' || bad 'report contract resolves validator from runtime root'
  grep -Fq '+<count> further <Severity> findings withheld' "$REPORT_CONTRACT" && ok 'report contract specifies severity overflow output' || bad 'report contract specifies severity overflow output'
  grep -Fq 'REFUSED-OVERWRITE' "$REPORT_CONTRACT" && ok 'report contract specifies collision refusal' || bad 'report contract specifies collision refusal'
  grep -Fq 'Missing or unsupported' "$REPORT_CONTRACT" && ok 'report contract specifies one scope clarification' || bad 'report contract specifies one scope clarification'
  grep -Fq 'explicit confirmation' "$REPORT_CONTRACT" && ok 'report contract gates fix planning on confirmation' || bad 'report contract gates fix planning on confirmation'
fi

installed="$TMP/installed runtime"
project="$TMP/audited project with spaces"
mkdir -p "$installed/scripts/ci" "$project/audits"
cp "$VALIDATOR" "$installed/scripts/ci/validate-audit-report.sh"
cp "$PATH_GUARD" "$installed/scripts/ci/prepare-audit-report-path.sh"
cp "$FINDING_FORMATTER" "$installed/scripts/ci/format-audit-findings.sh"

for scope in complete research product design build quality docs delivery; do
  report="$project/audits/audit-report-$scope-2026-09-27-contract.md"
  write_report "$report" "$scope" COMPLETE '0 Critical / 1 Major / 0 Minor / 0 Nice' '[Major] Supported finding.'
  if bash "$installed/scripts/ci/validate-audit-report.sh" --root "$project" "$report" >/dev/null; then
    ok "installed validator accepts $scope report"
  else
    bad "installed validator accepts $scope report"
  fi
done

clean="$project/audits/audit-report-build-2026-09-27-clean.md"
write_report "$clean" build COMPLETE '0 Critical / 0 Major / 0 Minor / 0 Nice' 'No findings in inspected surfaces.'
if bash "$installed/scripts/ci/validate-audit-report.sh" --root "$project" "$clean" >/dev/null; then
  ok 'clean report with zero severity counts passes'
else
  bad 'clean report with zero severity counts passes'
fi

incomplete="$project/audits/audit-report-quality-2026-09-27-incomplete.md"
write_report "$incomplete" quality INCOMPLETE '0 Critical / 0 Major / 0 Minor / 0 Nice' 'PENDING: required artifact was inaccessible.'
if bash "$installed/scripts/ci/validate-audit-report.sh" --root "$project" "$incomplete" >/dev/null; then
  ok 'incomplete report with the eight headings passes structural validation'
else
  bad 'incomplete report with the eight headings passes structural validation'
fi

echo '=== routing fixtures ==='
for expected in \
  'Sefi department audit|systems-auditor' \
  'systems-audit|systems-auditor' \
  'UI audit|ui-ux-designer' \
  'trust boundary|security-engineer' \
  'post-build|qa-engineer'; do
  grep -qxF "$expected" "$FIXTURES" && ok "fixture $expected" || bad "fixture $expected"
done
if bash "$CORE/scripts/ci/validate-routing.sh" >/dev/null; then
  ok 'routing fixtures resolve in the precedence table'
else
  bad 'routing fixtures resolve in the precedence table'
fi

echo '=== report allocation collision ==='
collision="$project/audits/audit-report-build-2026-09-27-collision.md"
printf '%s\n' 'existing report must remain unchanged' > "$collision"
if bash "$installed/scripts/ci/prepare-audit-report-path.sh" --root "$project" --scope build --report "$collision" > "$TMP/collision-result" 2>/dev/null; then
  bad 'pre-existing compliant report path refuses overwrite'
elif grep -qxF 'STATUS: REFUSED-OVERWRITE' "$TMP/collision-result" \
  && grep -qxF 'existing report must remain unchanged' "$collision"; then
  ok 'pre-existing compliant report path refuses overwrite without modifying it'
else
  bad 'pre-existing compliant report path refuses overwrite without modifying it'
fi

echo '=== capped finding presentation ==='
cat > "$TMP/findings.tsv" <<'EOF'
Research	Minor	minor one
Research	Major	major one
Research	Critical	critical one
Research	Major	major two
Research	Minor	minor two
Research	Major	major three
Research	Major	major four
Research	Major	major five
Research	Major	major six
EOF
if bash "$installed/scripts/ci/format-audit-findings.sh" < "$TMP/findings.tsv" > "$TMP/formatted-findings" 2>/dev/null \
  && [ "$(grep -c '^\[' "$TMP/formatted-findings")" -eq 5 ] \
  && sed -n '1p' "$TMP/formatted-findings" | grep -qxF '[Critical] critical one' \
  && sed -n '2p' "$TMP/formatted-findings" | grep -qxF '[Major] major one' \
  && grep -qxF '+2 further Major findings withheld (cap 5)' "$TMP/formatted-findings" \
  && grep -qxF '+2 further Minor findings withheld (cap 5)' "$TMP/formatted-findings"; then
  ok 'findings are severity ordered, capped at five, and report exact overflow totals'
else
  bad 'findings are severity ordered, capped at five, and report exact overflow totals'
fi

cat > "$TMP/complete-findings.tsv" <<'EOF'
Research	Major	research finding 1
Research	Major	research finding 2
Research	Major	research finding 3
Research	Major	research finding 4
Research	Major	research finding 5
Research	Major	research finding 6
Product	Major	product finding 1
Product	Major	product finding 2
Product	Major	product finding 3
Product	Major	product finding 4
Product	Major	product finding 5
Product	Major	product finding 6
EOF
if bash "$installed/scripts/ci/format-audit-findings.sh" < "$TMP/complete-findings.tsv" > "$TMP/complete-formatted-findings" 2>/dev/null \
  && [ "$(grep -c '^\[' "$TMP/complete-formatted-findings")" -eq 10 ] \
  && sed -n '1p' "$TMP/complete-formatted-findings" | grep -qxF '[Major] research finding 1' \
  && sed -n '6p' "$TMP/complete-formatted-findings" | grep -qxF '+1 further Major findings withheld (cap 5)' \
  && sed -n '7p' "$TMP/complete-formatted-findings" | grep -qxF '[Major] product finding 1' \
  && sed -n '12p' "$TMP/complete-formatted-findings" | grep -qxF '+1 further Major findings withheld (cap 5)'; then
  ok 'complete audit caps and overflows each department independently'
else
  bad 'complete audit caps and overflows each department independently'
fi

if printf 'Research\tMajor\n' | bash "$installed/scripts/ci/format-audit-findings.sh" >/dev/null 2>&1; then
  bad 'formatter rejects malformed three-column findings'
else
  ok 'formatter rejects malformed three-column findings'
fi

if printf 'Unsupported\tMajor\tfinding\n' | bash "$installed/scripts/ci/format-audit-findings.sh" >/dev/null 2>&1; then
  bad 'formatter rejects unsupported departments'
else
  ok 'formatter rejects unsupported departments'
fi

if [ "$fail" -ne 0 ]; then
  echo "test-systems-audit-behavior: $fail failure(s)" >&2
  exit 1
fi
echo 'test-systems-audit-behavior: OK'
