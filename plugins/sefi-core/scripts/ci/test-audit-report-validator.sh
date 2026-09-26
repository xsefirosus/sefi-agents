#!/usr/bin/env bash
# Regression coverage for validate-audit-report.sh physical containment.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
VALIDATOR_SOURCE="${AUDIT_REPORT_VALIDATOR_SOURCE:-$ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh}"

if [ ! -f "$VALIDATOR_SOURCE" ]; then
  echo "FAIL: validator source is unavailable: $VALIDATOR_SOURCE" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-audit-validator.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; fail=$((fail + 1)); }

report_body() {
  printf '%s\n' \
    '## Summary' \
    '## Scope' \
    '## Method' \
    '## Findings' \
    'Major finding' \
    '## Fixes' \
    '## Improvements' \
    '## Nice-to-haves' \
    '## Follow-up'
}

make_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/plugins/sefi-core/scripts/ci" "$fixture/audits" "$fixture/outside"
  cp "$VALIDATOR_SOURCE" "$fixture/plugins/sefi-core/scripts/ci/validate-audit-report.sh"
}

run_validator() {
  local fixture="$1" report="$2"
  bash "$fixture/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$report"
}

echo '=== valid report and preserved report checks ==='
fixture="$TMP/fixture with spaces"
make_fixture "$fixture"
mkdir -p "$fixture/audits/reports with spaces"
valid="$fixture/audits/reports with spaces/audit-report-build-2026-09-26-session.md"
report_body > "$valid"
if run_validator "$fixture" "$valid" >/dev/null 2>&1; then
  ok 'valid report beneath audits with spaces passes'
else
  bad 'valid report beneath audits with spaces passes'
fi

scanned="$fixture/audits/audit-report-build-2026-09-26-scanned.md"
report_body > "$scanned"
if bash "$fixture/plugins/sefi-core/scripts/ci/validate-audit-report.sh" >/dev/null 2>&1; then
  ok 'default report scan accepts a valid generated report'
else
  bad 'default report scan accepts a valid generated report'
fi

missing_heading="$fixture/audits/audit-report-build-2026-09-26-missing.md"
grep -v '^## Fixes$' "$valid" > "$missing_heading"
if run_validator "$fixture" "$missing_heading" >/dev/null 2>&1; then
  bad 'missing skeleton heading fails'
else
  ok 'missing skeleton heading fails'
fi

unsupported_scope="$fixture/audits/audit-report-frontend-2026-09-26-session.md"
report_body > "$unsupported_scope"
if run_validator "$fixture" "$unsupported_scope" >/dev/null 2>&1; then
  bad 'unsupported scope fails'
else
  ok 'unsupported scope fails'
fi

echo '=== traversal containment ==='
outside="$fixture/outside/audit-report-build-2026-09-26-outside.md"
report_body > "$outside"
if run_validator "$fixture" "$fixture/audits/../outside/audit-report-build-2026-09-26-outside.md" >/dev/null 2>&1; then
  bad 'audits traversal escape fails'
else
  ok 'audits traversal escape fails'
fi

echo '=== symlink containment ==='
symlink_fixture="$TMP/symlink fixture"
make_fixture "$symlink_fixture"
rmdir "$symlink_fixture/audits"
if ln -s "$symlink_fixture/outside-audits" "$symlink_fixture/audits" 2>/dev/null \
  && [ -L "$symlink_fixture/audits" ]; then
  mkdir -p "$symlink_fixture/outside-audits"
  root_link_report="$symlink_fixture/outside-audits/audit-report-build-2026-09-26-root-link.md"
  report_body > "$root_link_report"
  if run_validator "$symlink_fixture" "$symlink_fixture/audits/audit-report-build-2026-09-26-root-link.md" >/dev/null 2>&1; then
    bad 'symlinked audits root fails'
  else
    ok 'symlinked audits root fails'
  fi
else
  printf '  SKIP symlinked audits root (host cannot create symlinks)\n'
fi

intermediate_fixture="$TMP/intermediate fixture"
make_fixture "$intermediate_fixture"
mkdir -p "$intermediate_fixture/audits/real reports"
intermediate_target="$intermediate_fixture/audits/real reports/audit-report-build-2026-09-26-intermediate-link.md"
report_body > "$intermediate_target"
if ln -s 'real reports' "$intermediate_fixture/audits/link" 2>/dev/null \
  && [ -L "$intermediate_fixture/audits/link" ]; then
  if run_validator "$intermediate_fixture" "$intermediate_fixture/audits/link/audit-report-build-2026-09-26-intermediate-link.md" >/dev/null 2>&1; then
    bad 'symlinked intermediate directory fails'
  else
    ok 'symlinked intermediate directory fails'
  fi
else
  printf '  SKIP symlinked intermediate directory (host cannot create symlinks)\n'
fi

final_fixture="$TMP/final fixture"
make_fixture "$final_fixture"
target="$final_fixture/audits/target.md"
report_body > "$target"
if ln -s 'target.md' "$final_fixture/audits/audit-report-build-2026-09-26-final-link.md" 2>/dev/null \
  && [ -L "$final_fixture/audits/audit-report-build-2026-09-26-final-link.md" ]; then
  if run_validator "$final_fixture" "$final_fixture/audits/audit-report-build-2026-09-26-final-link.md" >/dev/null 2>&1; then
    bad 'symlinked final report fails'
  else
    ok 'symlinked final report fails'
  fi
else
  printf '  SKIP symlinked final report (host cannot create symlinks)\n'
fi

if [ "$fail" -ne 0 ]; then
  echo "test-audit-report-validator: $fail failure(s)" >&2
  exit 1
fi
echo 'test-audit-report-validator: OK'
