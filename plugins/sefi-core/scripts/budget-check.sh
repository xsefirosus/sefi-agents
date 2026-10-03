#!/usr/bin/env bash
# budget-check.sh [--scope run|daily|dispatch] [--spent <usd>] [--pending <usd>] [--config <path>] [--harness <name>]
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
HARNESS_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spent)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "budget-check: --spent requires a value" >&2; exit 2; }
      SPENT_ARG="$2"; shift 2 ;;
    --pending)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "budget-check: --pending requires a value" >&2; exit 2; }
      PENDING_ARG="$2"; shift 2 ;;
    --scope)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "budget-check: --scope requires a value" >&2; exit 2; }
      SCOPE="$2"; shift 2 ;;
    --config)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "budget-check: --config requires a path" >&2; exit 2; }
      CONFIG="$2"; shift 2 ;;
    --harness)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "budget-check: --harness requires a value" >&2; exit 2; }
      case "$2" in
        opencode|hermes|codex|claude-code|claude) HARNESS_ARG="$2" ;;
        *) echo "budget-check: unknown harness '$2' (expected opencode, hermes, codex, claude-code, or claude)" >&2; exit 2 ;;
      esac
      shift 2 ;;
    *) echo "budget-check: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -f "$CONFIG" ] || { echo "budget-check: $CONFIG not found" >&2; exit 2; }

get_cap() {
  awk -F: -v key="$1" '
    $1 == key { count++; value=$2; sub(/[[:space:]]*#.*/, "", value); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value) }
    END { if (count == 1) print value }
  ' "$CONFIG"
}

case "$SCOPE" in
  run)      CAP="$(get_cap per_run_usd_cap)" ;;
  dispatch) CAP="$(get_cap per_dispatch_usd_cap)" ;;
  daily)    CAP="$(get_cap daily_usd_cap)" ;;
  *) echo "budget-check: unknown scope '$SCOPE' (expected run, daily, or dispatch)" >&2; exit 2 ;;
esac

# Spend-mode switch (docs/BUDGET.md): dollar-denominated scopes enforce only when
# billing is metered. On flat or free plans there is no per-dollar spend to bound --
# and ccusage-imputed dollars on free usage must never block work -- so the dollar
# check is skipped with an explicit recorded reason. An explicit billing_mode in the
# config always wins. When the key is absent, a per-harness default applies:
# opencode and hermes resolve free, codex and claude-code resolve flat; no (or an
# unrecognized) harness signal resolves metered, fail-closed. The harness comes from
# --harness, then $SEFI_HARNESS, then the machine-local .sefi/harness marker written
# by /sefi:init. Non-dollar discipline (retry caps, reply caps, minimization,
# worktree caps) lives outside this script and stays always on regardless of mode.
default_billing_mode() {
  # default_billing_mode -- print the billing_mode for a config without the key.
  # Never fails: ambient signals ($SEFI_HARNESS, the marker file) sanitize to
  # metered on any surprise, exactly like write-shared-memory-mirror.sh falls back
  # to unknown-harness. Only the explicit --harness flag is validated strictly
  # (at arg-parse time above), because it is an API claim, not an ambient signal.
  local h="unknown" marker=""
  if [ -n "$HARNESS_ARG" ]; then
    h="$HARNESS_ARG"
  elif [ -n "${SEFI_HARNESS:-}" ]; then
    case "$SEFI_HARNESS" in
      opencode|hermes|codex|claude-code|claude) h="$SEFI_HARNESS" ;;
    esac
  elif [ -f .sefi/harness ]; then
    marker="$(head -n1 .sefi/harness 2>/dev/null | tr -d '\r\n' | tr -d '[:space:]')"
    case "$marker" in
      opencode|hermes|codex|claude-code|claude) h="$marker" ;;
    esac
  fi
  case "$h" in
    opencode|hermes) printf 'free\n' ;;
    codex|claude-code|claude) printf 'flat\n' ;;
    *) printf 'metered\n' ;;
  esac
}

BILLING_MODE="$(get_cap billing_mode)"
BILLING_DEFAULTED=0
if [ -z "$BILLING_MODE" ]; then
  BILLING_MODE="$(default_billing_mode)"
  BILLING_DEFAULTED=1
fi
if [ "$(grep -c '^billing_mode:' "$CONFIG" || true)" -gt 1 ]; then
  echo "budget-check: billing_mode is ambiguous in $CONFIG (declared more than once)" >&2; exit 2
fi
case "$BILLING_MODE" in
  metered) : ;;
  flat|free)
    if [ "$BILLING_DEFAULTED" -eq 1 ]; then
      echo "budget-check: skip scope=$SCOPE billing_mode=$BILLING_MODE -- dollar caps do not apply under $BILLING_MODE billing (per-harness default; set billing_mode explicitly to override); non-dollar discipline stays always on" >&2
    else
      echo "budget-check: skip scope=$SCOPE billing_mode=$BILLING_MODE -- dollar caps do not apply under $BILLING_MODE billing; non-dollar discipline stays always on" >&2
    fi
    exit 0 ;;
  *) echo "budget-check: billing_mode '$BILLING_MODE' is invalid in $CONFIG (expected metered, flat, or free)" >&2; exit 2 ;;
esac

is_number() {
  # A bare `awk '{print $1+0}'` coerces "null", "" and "abc" to 0 -- which is precisely how
  # a broken telemetry source turns this gate into a no-op that always passes. Validate
  # before any arithmetic touches the value.
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_number "$PENDING_ARG" || { echo "budget-check: --pending '$PENDING_ARG' is not a number" >&2; exit 2; }
is_number "$CAP" && awk -v c="$CAP" 'BEGIN { exit !(c + 0 > 0) }' \
  || { echo "budget-check: cap for scope '$SCOPE' must be one positive unambiguous number in $CONFIG" >&2; exit 2; }

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
