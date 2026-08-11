#!/usr/bin/env bash
# budget-check.sh [--scope run|daily|dispatch] [--spent <usd>] [--pending <usd>] [--config <path>]
# Enforce caps from config/budget.yml. Uses ccusage for real local spend when available
# (offline, no network); else the caller-supplied --spent. ccusage is optional -- the
# fallback keeps the zero-dependency install intact. --pending adds a not-yet-spent
# estimate (e.g. the next dispatch's projected cost) before comparing against the cap, so a
# daily-scope check can catch an overrun BEFORE it happens instead of only after
# ccusage/--spent reports it as already spent.
#
# Exit codes (a caller must be able to tell these apart -- collapsing them is the bug this
# script has now been fixed for twice):
#   0  within cap
#   1  EXCEEDED -- measured spend is over the cap
#   2  usage error (bad argument)
#   3  CANNOT MEASURE -- no usable spend source; the cap was never checked
# Both 1 and 3 are fail-closed. A caller that only tests "nonzero" stays correct; one that
# wants to distinguish "you blew the budget" from "I cannot tell" now can.
set -euo pipefail

SPENT_ARG=""
PENDING_ARG="0"
SCOPE="daily"
CONFIG="config/budget.yml"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spent)   SPENT_ARG="${2:-}"; shift 2 ;;
    --pending) PENDING_ARG="${2:-0}"; shift 2 ;;
    --scope)   SCOPE="${2:-daily}"; shift 2 ;;
    --config)  CONFIG="${2:-}"; shift 2 ;;
    *) echo "budget-check: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -f "$CONFIG" ] || { echo "budget-check: $CONFIG not found" >&2; exit 1; }

get_cap() { sed -n "s/^$1:[[:space:]]*\([0-9][0-9.]*\).*/\1/p" "$CONFIG" | head -1; }

case "$SCOPE" in
  run)      CAP="$(get_cap per_run_usd_cap)" ;;
  dispatch) CAP="$(get_cap per_dispatch_usd_cap)" ;;
  daily|*)  CAP="$(get_cap daily_usd_cap)" ;;
esac
[ -n "${CAP:-}" ] || { echo "budget-check: cap for scope '$SCOPE' missing in $CONFIG" >&2; exit 1; }

is_number() {
  # A bare `awk '{print $1+0}'` coerces "null", "" and "abc" to 0 -- which is precisely how
  # a broken telemetry source turns this gate into a no-op that always passes. Validate
  # before any arithmetic touches the value.
  case "${1:-}" in
    ''|.|*[!0-9.]*|*.*.*) return 1 ;;
    *) return 0 ;;
  esac
}

is_number "$PENDING_ARG" || { echo "budget-check: --pending '$PENDING_ARG' is not a number" >&2; exit 2; }

today="$(date +%Y-%m-%d)"
spent=""
source="none"

if command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # Real local spend from the tool's own ledger (Claude JSONL / Hermes state.db /
  # OpenCode db) - offline. The pipeline is guarded rather than bare: under `set -e` plus
  # `pipefail` a ccusage crash aborts the whole script with a bare exit 1, which a caller
  # reading only the exit code cannot tell apart from EXCEEDED.
  ccusage_out=""
  if ccusage_out="$(ccusage daily --since "$today" --until "$today" --json --offline 2>/dev/null \
      | jq -r '[.. | .totalCost? // empty] | add // 0' 2>/dev/null)" && is_number "$ccusage_out"; then
    spent="$ccusage_out"
    source="ccusage"
  else
    # Present but unusable (crashed, empty, or emitted `null`). Say so out loud and fall
    # through to --spent; never silently treat an unreadable ledger as zero spend.
    echo "budget-check: ccusage on PATH but returned no usable figure (got '${ccusage_out:-<none>}'); falling back" >&2
  fi
fi

if [ -z "$spent" ] && [ -n "$SPENT_ARG" ]; then
  is_number "$SPENT_ARG" || { echo "budget-check: --spent '$SPENT_ARG' is not a number" >&2; exit 2; }
  spent="$SPENT_ARG"        # caller-supplied claim (0 is a valid claim of zero spend)
  source="--spent"
fi

if [ -z "$spent" ]; then
  # No usable spend source: ccusage/jq absent or broken AND no --spent supplied. A gate
  # that cannot measure cannot certify, so it fails rather than passing a check it never
  # performed. This is the difference between "the caller says zero" and "nobody knows".
  echo "budget-check: CANNOT MEASURE scope=$SCOPE cap=$CAP -- no usable spend source (ccusage/jq absent or returning nothing, and --spent not supplied); the cap was NOT checked. Pass --spent <usd> (0 asserts zero spend) or install ccusage." >&2
  exit 3
fi

# Projected total = realized spend + pending (not-yet-spent) estimate for this check.
projected="$(awk -v s="$spent" -v p="$PENDING_ARG" 'BEGIN{print (s+0)+(p+0)}')"

# Float-safe comparison; exceeded when projected > cap.
if awk -v a="$projected" -v b="$CAP" 'BEGIN{exit !((a+0) > (b+0))}'; then
  echo "budget-check: EXCEEDED scope=$SCOPE spent=$spent pending=$PENDING_ARG projected=$projected cap=$CAP source=$source" >&2
  exit 1
fi
echo "budget-check: ok scope=$SCOPE spent=$spent pending=$PENDING_ARG projected=$projected cap=$CAP source=$source" >&2
exit 0
