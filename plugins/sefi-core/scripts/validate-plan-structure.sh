#!/usr/bin/env bash
# validate-plan-structure.sh -- reject plan files missing required headings, an undeclared
# tool dependency, or a step with no dependency marker. Exit 1 if any plan in state/ is
# malformed; exit 0 if all pass or no plans exist.
#
# The two checks beyond headings exist because the plan is the artifact three other agents
# consume, and each was guessing at something the planner knew:
#   - `(needs: ...)` per step: the engineering-manager's protocol says "sequence, do not
#     parallel-guess", but a flat checkbox list gave it nothing to sequence FROM, so
#     max_parallel_worktrees was unusable without guessing which steps were independent.
#   - `## Requires Tools`: loops declare requires-tools and get probed; a plan whose steps
#     shell out to gh or docker declared nothing, so the probe could not cover it.
set -uo pipefail

required_headings=("Objective" "Steps" "Files Touched" "Requires Tools" "Risks" "Done Criteria")

errors=0

for plan in state/plan-*.md; do
  [ -f "$plan" ] || continue

  for heading in "${required_headings[@]}"; do
    grep -q "^## $heading" "$plan" || {
      echo "VALIDATION FAIL: $plan missing '## $heading'" >&2
      errors=$((errors + 1))
    }
  done

  # Every checkbox step must declare its dependencies -- `(needs: -)` for none.
  while IFS= read -r step; do
    case "$step" in
      *"(needs:"*) : ;;
      *) echo "VALIDATION FAIL: $plan step has no '(needs: ...)' marker: $step" >&2
         errors=$((errors + 1)) ;;
    esac
  done < <(awk '/^## Steps/{p=1;next} /^## /{p=0} p && /^- \[ \]/' "$plan")

  # Requires Tools must have a body: "none" is a deliberate declaration, blank is an
  # omission, and the difference is exactly what the probe needs to know.
  tools_body="$(awk '/^## Requires Tools/{p=1;next} /^## /{p=0} p' "$plan" | tr -d '[:space:]')"
  [ -n "$tools_body" ] || {
    echo "VALIDATION FAIL: $plan has an empty '## Requires Tools' (use 'none' if it shells out to nothing)" >&2
    errors=$((errors + 1))
  }
done

[ "$errors" -eq 0 ] || exit 1
exit 0
