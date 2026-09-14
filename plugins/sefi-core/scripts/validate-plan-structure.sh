#!/usr/bin/env bash
# validate-plan-structure.sh [--file <plan-file>]
# Validate the plan artifact consumed by the scheduler and dispatch gates. With no argument,
# retain the historic state/plan-*.md discovery mode.
set -uo pipefail

required_headings=("Objective" "Steps" "Files Touched" "Requires Tools" "Risks" "Done Criteria")
errors=0

usage() { echo "validate-plan-structure: usage: validate-plan-structure.sh [--file <plan-file>]" >&2; }
trimmed_section() {
  awk -v heading="$1" '
    $0 == "## " heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$2" | tr -d '[:space:]'
}
fail() { echo "VALIDATION FAIL: $1" >&2; errors=$((errors + 1)); }

validate_plan() {
  local plan="$1" heading body rows n d p progressed ready
  for heading in "${required_headings[@]}"; do
    if ! grep -qF "## $heading" "$plan"; then
      fail "$plan missing '## $heading'"
      continue
    fi
    body="$(trimmed_section "$heading" "$plan")"
    [ -n "$body" ] || fail "$plan has an empty '## $heading'"
  done

  rows="$(awk '
    /^## Steps$/ { in_steps=1; next }
    in_steps && /^## / { exit }
    in_steps && /^- \[[ xX]\][[:space:]]*[0-9]+\./ {
      line=$0
      match(line, /^- \[[ xX]\][[:space:]]*[0-9]+/)
      id=substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", id)
      if (match(line, /\(needs:[^)]*\)/)) {
        dep=substr(line, RSTART, RLENGTH)
        sub(/^\(needs:[[:space:]]*/, "", dep); sub(/\)$/, "", dep); gsub(/[[:space:]]/, "", dep)
      } else dep="MALFORMED"
      print id "\t" dep
    }
  ' "$plan")"
  [ -n "$rows" ] || { fail "$plan has no parseable numbered steps"; return; }

  declare -A seen=() deps=() processed=()
  while IFS=$'\t' read -r n d; do
    if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
      fail "$plan has nonpositive step id '$n'"
      continue
    fi
    if [ -n "${seen[$n]:-}" ]; then
      fail "$plan repeats step id $n"
      continue
    fi
    seen[$n]=1; deps[$n]="$d"
    if ! [[ "$d" == "-" || "$d" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
      fail "$plan step $n has invalid '(needs: ...)' marker"
    fi
  done <<< "$rows"

  for n in "${!deps[@]}"; do
    d="${deps[$n]}"; [ "$d" = "-" ] && continue
    declare -A dep_seen=()
    IFS=',' read -ra parts <<< "$d"
    for p in "${parts[@]}"; do
      [ -n "${seen[$p]:-}" ] || fail "$plan step $n depends on missing step $p"
      [ -z "${dep_seen[$p]:-}" ] || fail "$plan step $n repeats dependency $p"
      dep_seen[$p]=1
    done
  done

  while :; do
    progressed=0
    for n in "${!deps[@]}"; do
      [ -n "${processed[$n]:-}" ] && continue
      d="${deps[$n]}"; ready=1
      if [ "$d" != "-" ]; then
        IFS=',' read -ra parts <<< "$d"
        for p in "${parts[@]}"; do [ -n "${processed[$p]:-}" ] || { ready=0; break; }; done
      fi
      if [ "$ready" -eq 1 ]; then processed[$n]=1; progressed=1; fi
    done
    [ "$progressed" -eq 1 ] || break
  done
  [ "${#processed[@]}" -eq "${#deps[@]}" ] || fail "$plan has a dependency cycle"
}

plans=()
case "${1:-}" in
  '') for p in state/plan-*.md; do [ -f "$p" ] && plans+=("$p"); done ;;
  --file)
    [ "$#" -eq 2 ] && [ -f "$2" ] || { usage; exit 2; }
    plans+=("$2") ;;
  *) usage; exit 2 ;;
esac

for plan in "${plans[@]}"; do validate_plan "$plan"; done
[ "$errors" -eq 0 ] || exit 1
exit 0
