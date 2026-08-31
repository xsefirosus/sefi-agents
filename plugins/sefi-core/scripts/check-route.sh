#!/usr/bin/env bash
# check-route.sh -- post-dispatch route-evidence assertion: did the harness actually run
# the model + reasoning effort this repo's tier map asked for?
#
#   check-route.sh <harness> <requested-tier> <session-record-placeholder>
#
# Resolves the requested tier to a concrete model + reasoning effort through the ONE
# resolver (scripts/model-for.sh -> config/model-map.yml), gates that resolved pair
# against a strict allowlist, then emits one compact JSON line:
#
#   {"status":..,"reason":..,"expected_model":..,"expected_effort":..,
#    "observed_model":..,"observed_effort":..}
#
# NO SESSION RECORD IS READ BY ANY HARNESS IN THIS VERSION. The third positional argument
# is accepted as a placeholder and is only non-printable-character-checked -- it is never
# opened, stat-ed, or followed. A prior revision shipped a rollout parser here; it was
# stripped because no harness has a confirmed rollout format in this repo and every parser
# variant tried had a fail-open shape (a decoy record could make a downgraded run report
# `match`). The parser returns only once a real, documented format exists.
#
# status is one of:
#   unavailable     the harness exposes no route readback this repo can trust. This is the
#                   result for EVERY harness with a real (non-`flexible`) resolved model
#                   today: claude-code (the CLI reports no per-agent model/usage), codex
#                   (rollout format unconfirmed -- see adapters/CODEX.md), hermes and
#                   opencode (only reached if a tier is ever pinned to a real id).
#   not-applicable  the requested tier resolves to the "flexible" sentinel
#                   (config/model-map.yml: opencode / hermes) -- there is no requested
#                   model id to compare, so a comparison would be meaningless.
#
# RESERVED, NOT EMITTED. `match`, `mismatch`, and `invalid` stay in the documented
# five-state vocabulary (skills/sefi-orchestration/references/harness-actions.md,
# state/metrics.md) as dormant future states. This script has NO code path that produces
# any of them: a future revision with a confirmed rollout format and a real JSON parser
# re-introduces them.
#
# Exit code: 0 only on `not-applicable`; non-zero on `unavailable`; exit 2 on a usage
# error. A usage error prints to stderr ONLY -- never a JSON status line.
#
# WHAT "VALIDATED" MEANS HERE, EXACTLY:
#   * <harness>, <requested-tier> and the placeholder are each rejected (exit 2, no JSON)
#     if they contain a non-printable character.
#   * <harness> must be one of: claude-code codex opencode hermes. Any other value is a
#     usage error (exit 2).
#   * The tier map's resolved model must be the literal "flexible" or match
#     ^[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}$; the resolved effort must be one of
#     "minimal low medium high xhigh none ultra". A malformed config/model-map.yml value
#     that is neither is a usage error (exit 2, no JSON) -- an unconstrained value can
#     never reach the JSON output, so every value emit() prints is constrained by
#     construction.
#   * The third positional argument is NEVER opened. No path parsing, no symlink check, no
#     size cap -- there is nothing to read.
#   * NO network calls. NO write side effects.

set -u

EFFORTS='minimal low medium high xhigh none ultra'

emit() {
  # emit <status> <reason> <expected_model> <expected_effort> <observed_model> <observed_effort>
  # Every value here is a fixed literal, a model id already constrained to
  # [A-Za-z0-9._:/-] (regex-gated below before it can get here), or an effort word from
  # EFFORTS -- none can carry a quote, a backslash, or free text into the JSON.
  printf '{"status":"%s","reason":"%s","expected_model":"%s","expected_effort":"%s","observed_model":"%s","observed_effort":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6"
}

usage() {
  printf 'ERROR: %s\n' "$1" >&2
  printf 'usage: check-route.sh <harness> <requested-tier> <session-record-placeholder>\n' >&2
  exit 2
}

# --- arguments -------------------------------------------------------------------------
# Keep a `--` end-of-options guard and reject any unknown option, but there are no
# options of our own any more.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    --*) usage "unknown option: $1" ;;
    *) break ;;
  esac
done

[ "$#" -eq 3 ] || usage "exactly three positional arguments are required: <harness> <requested-tier> <session-record-placeholder>"
HARNESS=$1
TIER=$2
REC=$3

[ -n "$HARNESS" ] || usage "harness must not be empty"
[ -n "$TIER" ]    || usage "requested tier must not be empty"
[ -n "$REC" ]     || usage "session-record placeholder must not be empty"

# Non-printable-character guard on EVERY argument (HARNESS and TIER are echoed to stderr
# in diagnostics; REC is retained only as an opaque placeholder): a control char in any of
# them is rejected outright.
for _arg in "$HARNESS" "$TIER" "$REC"; do
  case "$_arg" in
    *[![:print:]]*) usage "an argument contains a non-printable character" ;;
  esac
done

case "$HARNESS" in
  claude-code|codex|opencode|hermes) : ;;
  *) usage "unsupported harness: $HARNESS (expected one of: claude-code codex opencode hermes)" ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
MODEL_FOR="$HERE/model-for.sh"
[ -f "$MODEL_FOR" ] || usage "model-for.sh not found beside check-route.sh"

# Route the tier/harness through the ONE resolver, every value BEHIND a `--`
# end-of-options guard so a hostile tier or harness starting with '-' is never a flag.
EXPECTED_MODEL=$(bash "$MODEL_FOR" -- "$HARNESS" "$TIER" 2>/dev/null) \
  || usage "cannot resolve a model for harness='$HARNESS' tier='$TIER' (unknown harness, unmapped tier, or unreadable model map)"
EXPECTED_EFFORT=$(bash "$MODEL_FOR" --reasoning -- "$HARNESS" "$TIER" 2>/dev/null) \
  || usage "cannot resolve a reasoning effort for harness='$HARNESS' tier='$TIER'"

# The tier map's output is a trust boundary: a malformed config/model-map.yml value must
# never flow unchecked into emit(). Constrain it to the same shape emit() promises.
if [ "$EXPECTED_MODEL" != "flexible" ]; then
  printf '%s' "$EXPECTED_MODEL" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}$' \
    || usage "the model map resolved a model id that is not a bare identifier for harness='$HARNESS' tier='$TIER': '$EXPECTED_MODEL'"
fi
case " $EFFORTS " in
  *" $EXPECTED_EFFORT "*) : ;;
  *) usage "the model map resolved a reasoning effort outside the allowlist ($EFFORTS) for harness='$HARNESS' tier='$TIER': '$EXPECTED_EFFORT'" ;;
esac

# --- the flexible sentinel: no requested model id exists, so a comparison is undefined ---
if [ "$EXPECTED_MODEL" = "flexible" ]; then
  emit "not-applicable" "tier-resolves-to-flexible" \
    "$EXPECTED_MODEL" "$EXPECTED_EFFORT" "" ""
  exit 0
fi

# --- a real requested route, but no readable session record on any harness this version ---
case "$HARNESS" in
  claude-code)
    emit "unavailable" "harness-exposes-no-route-readback" \
      "$EXPECTED_MODEL" "$EXPECTED_EFFORT" "" ""
    ;;
  codex)
    emit "unavailable" "codex-rollout-format-unconfirmed" \
      "$EXPECTED_MODEL" "$EXPECTED_EFFORT" "" ""
    ;;
  hermes)
    emit "unavailable" "harness-model-readback-undocumented" \
      "$EXPECTED_MODEL" "$EXPECTED_EFFORT" "" ""
    ;;
  opencode)
    emit "unavailable" "session-record-format-undocumented" \
      "$EXPECTED_MODEL" "$EXPECTED_EFFORT" "" ""
    ;;
  *)
    usage "unsupported harness: $HARNESS"
    ;;
esac
exit 1
