#!/usr/bin/env bash
# budget-check.sh [--scope run|daily|dispatch] [--spent <usd>] [--pending <usd>] [--config <path>]
#                 [--harness opencode|hermes|codex|claude-code|claude]
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

need_value() {
  # need_value <flag> <next-token> -- succeed only when the flag is followed by a real value.
  # A following flag is a MISSING value, not a value: without this, "--harness --config x"
  # consumed "--config" as the harness name and reported "unknown harness '--config'",
  # pointing the operator at the wrong flag entirely. Every value-taking flag shares this
  # one check so the message is the same wherever the mistake is made.
  case "${2:-}" in
    '')  echo "budget-check: $1 requires a value (no argument follows it)" >&2; return 1 ;;
    -*)  echo "budget-check: $1 requires a value (got flag '${2}')" >&2; return 1 ;;
  esac
  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spent)
      need_value "$1" "${2:-}" || exit 2
      SPENT_ARG="$2"; shift 2 ;;
    --pending)
      need_value "$1" "${2:-}" || exit 2
      PENDING_ARG="$2"; shift 2 ;;
    --scope)
      need_value "$1" "${2:-}" || exit 2
      SCOPE="$2"; shift 2 ;;
    --config)
      need_value "$1" "${2:-}" || exit 2
      CONFIG="$2"; shift 2 ;;
    --harness)
      need_value "$1" "${2:-}" || exit 2
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
# unrecognized) harness signal resolves metered, fail-closed. A key that is present
# but has no value is a usage error, not a request for that default. The harness
# comes from --harness, then $SEFI_HARNESS, then the machine-local .sefi/harness
# marker written by /sefi:init (claude is accepted as an alias of claude-code).
# Non-dollar discipline (retry caps, reply caps, minimization, worktree caps) lives
# outside this script and stays always on regardless of mode.
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
    # Guarded, because what the guard costs is one line and what skipping it costs is the
    # exit code a caller acts on. An unguarded `marker="$(head ...)"` has two failure modes:
    # where errexit applies to the assignment (the function called directly), the script dies
    # with a bare exit 1 that no reader can tell from EXCEEDED; inside this script's actual
    # call path -- `BILLING_MODE="$(default_billing_mode)"` -- errexit does not reach the
    # substitution, so the failure is swallowed instead and the marker silently becomes empty.
    # Either way nothing names the unreadable marker. Now it is named, and "no signal" is
    # treated explicitly: sanitize to metered, say so, fail closed.
    if ! marker="$(head -n1 .sefi/harness 2>/dev/null | tr -d '\r\n' | tr -d '[:space:]')"; then
      marker=""
      echo "budget-check: .sefi/harness is present but unreadable; the per-harness default falls back to metered (fail-closed)" >&2
    fi
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

billing_declared="$(grep -c '^billing_mode:' "$CONFIG" || true)"
if [ "$billing_declared" -gt 1 ]; then
  echo "budget-check: billing_mode is ambiguous in $CONFIG (declared more than once)" >&2; exit 2
fi
BILLING_MODE="$(get_cap billing_mode)"
BILLING_DEFAULTED=0
if [ "$billing_declared" -eq 0 ]; then
  BILLING_MODE="$(default_billing_mode)"
  BILLING_DEFAULTED=1
elif [ -z "$BILLING_MODE" ]; then
  # Absent is absent; declared-with-no-value is a config error. Reading an empty value as
  # "use the default" is how a metered install silently becomes a skip because someone
  # emptied the key or left only a comment -- the operator asked for nothing, which is not
  # the same as asking for the per-harness default.
  echo "budget-check: billing_mode is declared with no value in $CONFIG (expected metered, flat, or free; remove the key entirely to use the per-harness default)" >&2
  exit 2
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
