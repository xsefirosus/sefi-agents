#!/usr/bin/env bash
# validate-audit-report.sh -- structural gate for systems-auditor reports. The auditor
# (/sefi:audit -> systems-auditor) writes exactly one fenced report per audit to
# audits/audit-report-<scope>-<timestamp>-<session>.md; this asserts the file that
# landed is actually shaped like one before anything downstream trusts it.
#
# Usage:
#   validate-audit-report.sh [--strict] [<report-path>]
#
#   --strict       accepted and ignored, for parity with the sibling validators
#                  run-all.sh forwards --strict to (this check has no warning tier).
#   <report-path>  one report file to check. Omit it to check every
#                  audits/audit-report-*.md under the repo root instead (vacuous
#                  pass when audits/ holds no reports -- reports are ignored-local,
#                  so CI checkouts normally have none).
#
# A report fails when its path is outside audits/, when any fixed skeleton heading
# is missing (## Summary, Scope, Method, Findings, Fixes, Improvements,
# Nice-to-haves, Follow-up), when no severity label (Critical/Major/Minor/Nice)
# appears outside the ## skeleton lines (so ## Nice-to-haves cannot satisfy its
# own gate), or when the scope token -- the segment between `audit-report-` and
# the next `-` in the file name -- is outside the allowlist (complete, research,
# product, design, build, quality, docs, delivery).
#
# Exit: 0 the report(s) are shaped like audit reports; 1 a shape check failed;
# 2 usage error (wrong arg count, unknown flag, or the path is not a file).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"

REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) shift ;;
    --*) echo "ERROR: unknown argument: $1" >&2; echo "usage: validate-audit-report.sh [--strict] [<report-path>]" >&2; exit 2 ;;
    *)
      if [ -n "$REPORT" ]; then
        echo "ERROR: at most one report path" >&2; echo "usage: validate-audit-report.sh [--strict] [<report-path>]" >&2; exit 2
      fi
      REPORT="$1"; shift ;;
  esac
done

errors=0

check_report() {
  # check_report <path> -- one file against the four shape checks.
  local file="$1" rel base rest scope h audits physical_dir physical_file logical_file current component relative
  rel="${file#"$ROOT"/}"

  audits="$ROOT/audits"
  if [ -L "$audits" ]; then
    echo "ERROR: $rel - audits root must not be a symlink"
    errors=$((errors + 1)); return
  fi
  audits="$(cd -P -- "$audits" 2>/dev/null && pwd -P)" || {
    echo "ERROR: $rel - canonical audits root is unavailable"; errors=$((errors + 1)); return;
  }
  physical_dir="$(cd -P -- "$(dirname -- "$file")" 2>/dev/null && pwd -P)" || {
    echo "ERROR: $rel - report path is outside audits/"; errors=$((errors + 1)); return;
  }
  physical_file="$physical_dir/$(basename -- "$file")"
  case "$physical_file" in "$audits"/*) : ;; *) echo "ERROR: $rel - report path is outside audits/"; errors=$((errors + 1)); return;; esac
  logical_file="$(cd -L -- "$(dirname -- "$file")" 2>/dev/null && pwd -L)/$(basename -- "$file")"
  case "$logical_file" in "$ROOT"/audits/*)
    relative="${logical_file#"$ROOT"/audits/}"; current="$ROOT/audits"
    IFS=/ read -r -a components <<< "${relative%/*}"
    for component in "${components[@]}"; do [ -z "$component" ] || { current="$current/$component"; [ ! -L "$current" ] || { echo "ERROR: $rel - report path contains a symlink"; errors=$((errors + 1)); return; }; }; done ;;
  esac
  if [ -L "$file" ]; then echo "ERROR: $rel - report file must not be a symlink"; errors=$((errors + 1)); return; fi

  for h in Summary Scope Method Findings Fixes Improvements Nice-to-haves Follow-up; do
    if ! grep -qE "^##[[:space:]]+$h([[:space:]]|$)" "$file"; then
      echo "ERROR: $rel - missing skeleton heading '## $h'"
      errors=$((errors + 1))
    fi
  done

  if ! grep -vE '^##[[:space:]]' "$file" | grep -qE '\b(Critical|Major|Minor|Nice)\b'; then
    echo "ERROR: $rel - no severity label (Critical/Major/Minor/Nice) outside the skeleton headings"
    errors=$((errors + 1))
  fi

  base="$(basename "$file")"
  case "$base" in
    audit-report-*-*)
      rest="${base#audit-report-}"
      scope="${rest%%-*}"
      case "$scope" in
        complete|research|product|design|build|quality|docs|delivery) : ;;
        *)
          echo "ERROR: $rel - scope token '$scope' is outside the allowlist (complete, research, product, design, build, quality, docs, delivery)"
          errors=$((errors + 1)) ;;
      esac ;;
    *)
      echo "ERROR: $rel - file name carries no audit-report-<scope>- scope token"
      errors=$((errors + 1)) ;;
  esac
}

if [ -n "$REPORT" ]; then
  if [ ! -f "$REPORT" ]; then
    echo "ERROR: $REPORT - report file not found" >&2; exit 2
  fi
  check_report "$REPORT"
  if [ "$errors" -ne 0 ]; then echo "validate-audit-report: $errors error(s)"; exit 1; fi
  echo "validate-audit-report: OK ($REPORT)"
  exit 0
fi

n=0
for f in "$ROOT"/audits/audit-report-*.md; do
  [ -e "$f" ] || continue
  n=$((n + 1))
  check_report "$f"
done

if [ "$errors" -ne 0 ]; then echo "validate-audit-report: $errors error(s)"; exit 1; fi
echo "validate-audit-report: OK ($n report(s) checked)"
