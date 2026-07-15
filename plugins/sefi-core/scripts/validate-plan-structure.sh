#!/usr/bin/env bash
# validate-plan-structure.sh -- reject plan files missing required headings (metagpt-batch2
# adoption). Exit 1 if any plan in state/ is malformed; exit 0 if all pass or no plans exist.
set -uo pipefail

required_headings=("Objective" "Steps" "Files Touched" "Risks" "Done Criteria")

for plan in state/plan-*.md; do
  [ -f "$plan" ] || continue
  for heading in "${required_headings[@]}"; do
    grep -q "^## $heading" "$plan" || {
      echo "VALIDATION FAIL: $plan missing '## $heading'" >&2
      exit 1
    }
  done
done
exit 0
