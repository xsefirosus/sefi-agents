#!/usr/bin/env bash
# budget-check.sh [--scope run|daily|dispatch] [--spent <usd>] [--pending <usd>] [--config <path>]
#                 [--harness opencode|hermes|codex|claude-code|claude|cline]
# Enforce caps from config/budget.yml. Uses ccusage for real local spend when available
# (offline, no network); else the caller-supplied --spent. ccusage is optional -- the
# fallback keeps the zero-dependency install intact. --pending adds a not-yet-spent
# estimate (e.g. the next dispatch's projected cost) before comparing against the cap, so a
# daily-scope check can catch an overrun BEFORE it happens instead of only after
# ccusage/--spent reports it as already spent.
#
# The config is resolved, in order: an explicit --config argument; config/budget.yml
# relative to the current working directory (the project-local config); budget-defaults.yml
# next to this script (what the installers ship into the installed scripts directory); then
# templates/config/budget.yml relative to the plugin root (a repo checkout). Only when none
# of those exists is the config missing. The old cwd-only default made every check run
# from outside a project root report "config/budget.yml not found" and exit 2 -- a gate
# that could not run at all, from the installed harness home or any unrelated directory.
#
# The harness identity behind the per-harness billing default is resolved, in order: the
# explicit --harness flag; $SEFI_HARNESS; the install marker (.sefi/harness next to the
# installed scripts, found relative to THIS script's own directory); the project marker
# (.sefi/harness in the working directory, then in the nearest parent directory that has
# one); then the fail-closed metered default. Every ambient signal sanitizes to metered on
# any surprise -- absent, unreadable, empty, or unrecognized -- so no signal can weaken a
# gate into a skip by accident.
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
CONFIG=""
CONFIG_GIVEN=0
HARNESS_ARG=""
# This script's own directory, resolved once. The install marker, the bundled defaults,
# and the repo template are all located relative to it, so a check run from an unrelated
# working directory still finds a config and a harness identity. `cd` + `pwd` (not
# `pwd -P`) keeps the LOGICAL path: an install whose scripts/ is a symlink into the
# source checkout must resolve the install marker next to the INSTALL, not next to the
# checkout.
HERE="$(cd "$(dirname "$0")" && pwd)"

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
      CONFIG="$2"; CONFIG_GIVEN=1; shift 2 ;;
    --harness)
      need_value "$1" "${2:-}" || exit 2
      case "$2" in
        opencode|hermes|codex|claude-code|claude|cline) HARNESS_ARG="$2" ;;
        *) echo "budget-check: unknown harness '$2' (expected opencode, hermes, codex, claude-code, claude, or cline)" >&2; exit 2 ;;
      esac
      shift 2 ;;
    *) echo "budget-check: unknown arg $1" >&2; exit 2 ;;
  esac
done

# Config discovery. An explicit --config is the caller's claim and is checked as given.
# Without one, the chain is the fallback-chain precedent already in this codebase
# (scripts/check-reply.sh:97): the project-local config first, then the bundled defaults
# that the installers ship next to the installed script, then the repo template.
#
# The message for a missing config is unchanged ("config/budget.yml not found", exit 2):
# what changed is that it is now reachable only when NO candidate exists, instead of
# whenever the working directory happened not to be the project root.
if [ "$CONFIG_GIVEN" -eq 1 ]; then
  [ -f "$CONFIG" ] || { echo "budget-check: $CONFIG not found" >&2; exit 2; }
else
  CONFIG=""
  candidate=""
  for candidate in "config/budget.yml" "$HERE/budget-defaults.yml" "$HERE/../templates/config/budget.yml"; do
    if [ -f "$candidate" ]; then
      CONFIG="$candidate"
      break
    fi
  done
  [ -n "$CONFIG" ] || { echo "budget-check: config/budget.yml not found" >&2; exit 2; }
fi

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
# opencode and hermes resolve free, codex, claude-code, and cline resolve flat; no
# (or an unrecognized) harness signal resolves metered, fail-closed. A key that is
# present but has no value is a usage error, not a request for that default. The
# harness comes from --harness, then $SEFI_HARNESS, then the install marker
# (.sefi/harness next to the installed scripts), then the project marker
# (.sefi/harness in the working directory or in the nearest parent directory that
# carries one) -- the last two written by the installers and by /sefi:init
# respectively; claude is accepted as an alias of claude-code. Non-dollar discipline
# (retry caps, reply caps, minimization, worktree caps) lives outside this script and
# stays always on regardless of mode.
default_billing_mode() {
  # default_billing_mode -- print the billing_mode for a config without the key.
  # Never fails: ambient signals ($SEFI_HARNESS, the marker files) sanitize to
  # metered on any surprise, exactly like write-shared-memory-mirror.sh falls back
  # to unknown-harness. Only the explicit --harness flag is validated strictly
  # (at arg-parse time above), because it is an API claim, not an ambient signal.
  #
  # The order is: the explicit --harness flag, then $SEFI_HARNESS, then the INSTALL
  # marker (the .sefi/harness file an installer writes next to the installed scripts,
  # found relative to this script's own directory so it resolves from any working
  # directory), then the PROJECT marker (.sefi/harness in the working directory, then
  # in the nearest parent directory that carries one), then the fail-closed default.
  #
  # Every new signal states the same fact -- which harness is running -- so none of
  # them can weaken a gate into a skip by surprise. A present-but-unusable signal
  # (unreadable, empty, unrecognized, or not a regular file) sanitizes to metered
  # and STOPS the search; an absent install marker falls through to the project
  # marker, and an absent project marker falls to metered. A set-but-empty or
  # unrecognized $SEFI_HARNESS also stops the search: a signal that is present but
  # says nothing usable is not permission to look for a weaker one.
  local h="unknown" resolved=""
  if [ -n "$HARNESS_ARG" ]; then
    h="$HARNESS_ARG"
  elif [ "${SEFI_HARNESS+set}" = set ]; then
    case "$SEFI_HARNESS" in
      opencode|hermes|codex|claude-code|claude|cline) h="$SEFI_HARNESS" ;;
      *)
        # Set but unusable: empty names nothing, and an unknown name is no better.
        # Leave h=unknown (metered) and never consult the markers, because a present
        # signal that is unusable is not permission to look for a weaker one.
        if [ -z "$SEFI_HARNESS" ]; then
          echo "budget-check: SEFI_HARNESS is set but empty; the per-harness default falls back to metered (fail-closed)" >&2
        else
          echo "budget-check: SEFI_HARNESS names no known harness; the per-harness default falls back to metered (fail-closed)" >&2
        fi ;;
    esac
  else
    resolved="$(harness_from_marker "$HERE/../.sefi/harness")"
    case "$resolved" in
      '!invalid')
        # The install marker is present but says nothing usable. That is a signal,
        # not an absence: sanitize to metered and do NOT consult the project marker,
        # because a bad higher-priority signal is not permission to look for a
        # weaker one.
        resolved="" ;;
      '')
        resolved="$(harness_from_project_marker)"
        if [ "$resolved" = '!invalid' ]; then
          resolved=""
        fi ;;
    esac
    if [ -n "$resolved" ]; then
      h="$resolved"
    fi
  fi
  case "$h" in
    opencode|hermes) printf 'free\n' ;;
    codex|claude-code|claude|cline) printf 'flat\n' ;;
    *) printf 'metered\n' ;;
  esac
}

harness_from_marker() {
  # harness_from_marker <path> -- print the harness name the marker declares, the
  # sentinel "!invalid" when the file is present but unreadable, empty, or names no
  # known harness, or nothing when the file is absent. The caller MUST treat the
  # sentinel as a present signal that sanitizes to metered, never as permission to
  # consult a farther marker: returning empty for both "absent" and "bad" is the
  # fail-open this function exists to prevent.
  # Always exits 0: this function is called from inside a command substitution, where a
  # non-zero status would be swallowed into an empty string anyway -- and an empty
  # string is exactly the ambiguity this function exists to remove.
  #
  # The read is guarded, because what the guard costs is one line and what skipping it
  # costs is the exit code a caller acts on. An unguarded `marker="$(head ...)"` has two
  # failure modes: where errexit applies to the assignment (the function called
  # directly), the script dies with a bare exit 1 that no reader can tell from
  # EXCEEDED; inside this script's actual call path -- `BILLING_MODE="$(default_billing_mode)"`
  # -- errexit does not reach the substitution, so the failure is swallowed instead and
  # the marker silently becomes empty. Either way nothing names the unreadable marker.
  # Now it is named, and "no signal" is treated explicitly: sanitize to metered, say
  # so, fail closed.
  local path="$1" marker=""
  # Absent means no directory entry at all. -e is false for a broken symlink and
  # -f is false for a directory, FIFO, or socket, so test both: a path that exists
  # but is not a readable regular file is a PRESENT-but-invalid signal, not an
  # absence -- otherwise it falls through to a weaker marker and can skip the cap.
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  if [ ! -f "$path" ]; then
    echo "budget-check: $path is present but not a readable regular file; the per-harness default falls back to metered (fail-closed)" >&2
    printf '!invalid\n'
    return 0
  fi
  if ! marker="$(head -n1 "$path" 2>/dev/null | tr -d '\r\n' | tr -d '[:space:]')"; then
    echo "budget-check: $path is present but unreadable; the per-harness default falls back to metered (fail-closed)" >&2
    printf '!invalid\n'
    return 0
  fi
  case "$marker" in
    opencode|hermes|codex|claude-code|claude|cline) printf '%s\n' "$marker" ;;
    *)
      echo "budget-check: $path names no known harness; the per-harness default falls back to metered (fail-closed)" >&2
      printf '!invalid\n' ;;
  esac
  return 0
}

harness_from_project_marker() {
  # harness_from_project_marker -- print the harness name the PROJECT marker declares,
  # or print nothing when there is none. The marker is looked for in the working
  # directory first and then in each parent directory, so a check run from a nested
  # directory inside a project still sees that project's harness identity instead of
  # falling back to metered for a reason that has nothing to do with the harness.
  #
  # The walk stops at the first marker it finds, parent or not: the nearest marker is
  # the project's own, and a present-but-bad one is propagated as "!invalid" so the
  # caller meters instead of skipping to a farther marker.
  local dir="$PWD" resolved=""
  while [ -n "$dir" ]; do
    if [ -e "$dir/.sefi/harness" ] || [ -L "$dir/.sefi/harness" ]; then
      resolved="$(harness_from_marker "$dir/.sefi/harness")"
      printf '%s' "$resolved"
      return 0
    fi
    if [ "$dir" = "/" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  return 0
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
