#!/usr/bin/env bash
# ready-steps.sh [--config <path>] <plan-file>
#
# Compute the ready set from a product-manager plan's `(needs: ...)` markers: the unchecked
# `- [ ] N.` steps whose dependencies are ALL checked, capped at `max_parallel_worktrees`
# from config/budget.yml. This is what engineering-manager.md protocol item 5 and
# morning-triage.loop.md's Handoff both already declared as the dispatch-set source before
# this script existed -- reasoning about markers in prose instead of running this.
#
# Exit codes follow budget-check.sh's precedent (a caller must be able to tell these apart):
#   0  ready set emitted to stdout, one step number per line
#   1  malformed -- a step has no (needs: ...) marker, a dep names a step that does not
#      exist in this plan, or the file has no parseable steps at all
#   2  usage error (bad argument, missing file, missing config key)
#   3  BLOCKED -- unchecked steps remain but none is ready (a dependency cycle, or every
#      unchecked step depends on another unchecked one)
#   4  COMPLETE -- every step in the plan is checked
# A silent empty stdout on success would let a caller mistake a cycle (3) or a finished
# plan (4) for "nothing is ready right now"; the distinct exit codes remove that ambiguity.
set -uo pipefail

CONFIG="config/budget.yml"
PLAN=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    -*) echo "ready-steps: unknown arg $1" >&2; exit 2 ;;
    *) PLAN="$1"; shift ;;
  esac
done

[ -n "$PLAN" ] || { echo "ready-steps: usage: ready-steps.sh [--config <path>] <plan-file>" >&2; exit 2; }
[ -f "$PLAN" ] || { echo "ready-steps: $PLAN not found" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "ready-steps: $CONFIG not found" >&2; exit 2; }

MAXPAR="$(sed -n 's/^max_parallel_worktrees:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONFIG" | head -1)"
[ -n "${MAXPAR:-}" ] || { echo "ready-steps: max_parallel_worktrees missing in $CONFIG" >&2; exit 2; }

# One TSV row per step: num, checked (0/1), deps ("-", "N", or "N,M,..."). A step with no
# (needs: ...) marker at all, or an empty one, reports MALFORMED in the deps column rather
# than being silently dropped -- validate-plan-structure.sh should have caught this already,
# but this script does not trust that it ran.
rows="$(awk '
  /^- \[[ xX]\][[:space:]]*[0-9]+\./ {
    line = $0
    checked = (line ~ /^- \[[xX]\]/) ? 1 : 0
    match(line, /^- \[[ xX]\][[:space:]]*[0-9]+/)
    numstr = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", numstr)
    lastneeds = ""; rest = line
    while (match(rest, /\(needs:[^)]*\)/)) {
      lastneeds = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
    }
    if (lastneeds == "") { print numstr "\t" checked "\tMALFORMED"; next }
    d = lastneeds
    sub(/^\(needs:[[:space:]]*/, "", d); sub(/\)[[:space:]]*$/, "", d); gsub(/[[:space:]]/, "", d)
    if (d == "") d = "MALFORMED"
    print numstr "\t" checked "\t" d
  }
' "$PLAN")"

[ -n "$rows" ] || { echo "ready-steps: no parseable steps in $PLAN" >&2; exit 1; }

nums=(); checked=(); deps=()
while IFS="$(printf '\t')" read -r n c d; do
  nums+=("$n"); checked+=("$c"); deps+=("$d")
done <<< "$rows"

is_known() {
  local target="$1" i
  for i in "${!nums[@]}"; do [ "${nums[$i]}" = "$target" ] && return 0; done
  return 1
}
is_checked_num() {
  local target="$1" i
  for i in "${!nums[@]}"; do
    [ "${nums[$i]}" = "$target" ] && { [ "${checked[$i]}" = "1" ] && return 0 || return 1; }
  done
  return 1
}

for i in "${!nums[@]}"; do
  if [ "${deps[$i]}" = "MALFORMED" ]; then
    echo "ready-steps: malformed -- step ${nums[$i]} has no (needs: ...) marker" >&2
    exit 1
  fi
done

for i in "${!nums[@]}"; do
  d="${deps[$i]}"
  [ "$d" = "-" ] && continue
  IFS=',' read -ra parts <<< "$d"
  for p in "${parts[@]}"; do
    if ! is_known "$p"; then
      echo "ready-steps: malformed -- step ${nums[$i]} depends on nonexistent step $p" >&2
      exit 1
    fi
  done
done

unchecked=0
ready=()
for i in "${!nums[@]}"; do
  [ "${checked[$i]}" = "1" ] && continue
  unchecked=$((unchecked + 1))
  d="${deps[$i]}"
  ok=1
  if [ "$d" != "-" ]; then
    IFS=',' read -ra parts <<< "$d"
    for p in "${parts[@]}"; do
      is_checked_num "$p" || { ok=0; break; }
    done
  fi
  [ "$ok" -eq 1 ] && ready+=("${nums[$i]}")
done

if [ "$unchecked" -eq 0 ]; then
  echo "ready-steps: COMPLETE -- all ${#nums[@]} step(s) checked" >&2
  exit 4
fi

if [ "${#ready[@]}" -eq 0 ]; then
  echo "ready-steps: BLOCKED -- $unchecked unchecked step(s) remain, none ready (a dependency cycle, or every unchecked step depends on another unchecked one)" >&2
  exit 3
fi

# Deterministic cap: lowest step numbers first when more are ready than max_parallel_worktrees allows.
sorted="$(printf '%s\n' "${ready[@]}" | sort -n | head -n "$MAXPAR")"
printf '%s\n' "$sorted"
emitted="$(printf '%s\n' "$sorted" | grep -c .)"
echo "ready-steps: $emitted ready (of $unchecked unchecked, cap $MAXPAR)" >&2
exit 0
