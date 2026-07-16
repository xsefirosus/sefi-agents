#!/usr/bin/env bash
# budget-check.sh [--scope run|daily|dispatch] [--spent <usd>] [--pending <usd>] [--config <path>]
# Enforce caps from config/budget.yml. Exits nonzero when a cap is exceeded. Uses ccusage
# for real local spend when available (offline, no network); else the caller-supplied
# --spent. ccusage is optional -- the fallback keeps the zero-dependency install intact.
# --pending adds a not-yet-spent estimate (e.g. the next dispatch's projected cost) before
# comparing against the cap, so a daily-scope check can catch an overrun BEFORE it happens
# instead of only after ccusage/--spent reports it as already spent.
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

today="$(date +%Y-%m-%d)"
if command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # real local spend from the tool's own ledger (Claude JSONL / Hermes state.db / OpenCode db) - offline
  spent="$(ccusage daily --since "$today" --until "$today" --json --offline \
    | jq '[.. | .totalCost? // empty] | add // 0')"
elif [ -n "$SPENT_ARG" ]; then
  spent="$SPENT_ARG"        # fallback: caller-supplied --spent (0 is a valid claim)
else
  # No spend source: ccusage/jq are absent AND no --spent was supplied. A gate that cannot
  # measure cannot certify, so it fails rather than passing a check it never performed.
  # This is the difference between "the caller says zero" and "nobody knows" -- collapsing
  # the two is what made this check a no-op on a stock CI runner.
  echo "budget-check: NO SPEND SOURCE scope=$SCOPE cap=$CAP -- ccusage/jq not on PATH and --spent not supplied; the cap cannot be checked. Pass --spent <usd> (0 asserts zero spend) or install ccusage." >&2
  exit 1
fi

# Projected total = realized spend + pending (not-yet-spent) estimate for this check.
projected="$(awk -v s="$spent" -v p="$PENDING_ARG" 'BEGIN{print (s+0)+(p+0)}')"

# Float-safe comparison; exceeded when projected > cap.
if awk -v a="$projected" -v b="$CAP" 'BEGIN{exit !((a+0) > (b+0))}'; then
  echo "budget-check: EXCEEDED scope=$SCOPE spent=$spent pending=$PENDING_ARG projected=$projected cap=$CAP" >&2
  exit 1
fi
echo "budget-check: ok scope=$SCOPE spent=$spent pending=$PENDING_ARG projected=$projected cap=$CAP" >&2
exit 0
