#!/usr/bin/env bash
# check-route.sh -- interpreter-resolving shim over check-route.py, the real route-evidence
# parser. THE PATH IS LOAD-BEARING: every `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh`
# reference in the agent/skill markdown (validate-script-refs.sh enforces the prefix) and
# the harness-neutral invocation resolve here, so this file keeps its exact name while the
# parsing logic lives in the sibling check-route.py.
#
# WHY A PYTHON PARSER. The previous jq-free POSIX-sh version was reduced across four review
# rounds for five fail-open shapes -- a decoy rollout record could make a downgraded run
# report `match`. A real `json.loads` per line plus top-level-only dict access cannot have
# those shapes. The "no Python in plugin scripts" rule was lifted by the human for this one
# post-dispatch script, on the same basis the repo already accepts python3 for
# benchmarks/scorecard.py as contributor tooling.
#
# Interpreter resolution: prefer `python3`, fall back to `python` (the dev Windows host's
# `python3` is the broken Microsoft Store stub; `python` is a real 3.11) -- each is accepted
# only if it runs AND reports version >= 3.11. If neither qualifies, this prints a "route
# check skipped" notice to stderr and exits 3, so a caller can tell "no interpreter" (3)
# apart from a real route verdict (0/1) or a usage error (2).
#
# Arguments are forwarded to check-route.py, which owns every validation, the model-for.sh
# resolution, and the JSON emit. See check-route.py's header for the status vocabulary and
# exit codes.
#
# EVERY POSITIONAL IS FORCED AFTER `--`. When at least three args are given, this shim
# execs `check-route.py -- "$@"`, so arguments 1, 2, AND 3+ (harness, tier, and the
# thread-id/record slot) all reach the parser as POSITIONALS -- never as options. A call
# site that expands an env-derived value UNQUOTED into ANY slot -- `$CODEX_THREAD_ID` in
# slot 3 (`check-route.sh codex mid $CODEX_THREAD_ID`), or a stray leading-dash word that
# word-splits into slot 1-2 -- lands after `--`: argparse then reports "unrecognized
# arguments" (or an unknown-harness usage error) and exits 2 with NO JSON. `--rollout-file`
# smuggling through the shim is structurally impossible; it can never redirect the check at
# an attacker-authored rollout. `--rollout-file` / `--sessions-dir` stay REGISTERED in
# build_parser: a DIRECT `python check-route.py ... --rollout-file X` (no `--`) still works
# -- that is the trusted contributor-test path. The `$# -lt 3` fallback preserves the
# existing "too few args -> argparse usage error, exit 2" and "--help" / "-h" (exit 0)
# behaviour.

set -u

# Locate this shim's own directory so we can find its sibling check-route.py. Use shell
# parameter expansion (cd/pwd are builtins) rather than external `dirname`, so this still
# resolves when PATH has been stripped bare for the interpreter-skip path below. A bare
# `$0` with no slash is NEVER resolved from $(pwd) -- a planted ./check-route.py there
# could otherwise be run; fall back to `command -v` instead, and if that fails too, refuse.
case "$0" in
  */*)
    HERE="$(cd "${0%/*}" 2>/dev/null && pwd)"
    ;;
  *)
    self="$(command -v -- "$0" 2>/dev/null || true)"
    case "$self" in
      */*) HERE="$(cd "${self%/*}" 2>/dev/null && pwd)" ;;
      *)   HERE="" ;;
    esac
    ;;
esac
PY="$HERE/check-route.py"
if [ -z "$HERE" ] || [ ! -f "$PY" ]; then
  printf '%s\n' \
    "check-route: cannot locate check-route.py next to $0; route check skipped" >&2
  exit 3
fi

# usable <interpreter-name> -- on PATH, executes, and is Python 3.11 or newer.
usable() {
  command -v "$1" >/dev/null 2>&1 || return 1
  "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' \
    >/dev/null 2>&1
}

# Resolve to the ABSOLUTE interpreter path (command -v result), not the bare name, so the
# exec is not a second PATH lookup at exec time.
INTERP=""
if usable python3; then
  INTERP="$(command -v python3)"
elif usable python; then
  INTERP="$(command -v python)"
fi

if [ -z "$INTERP" ]; then
  printf '%s\n' \
    'check-route: no python3 or python 3.11+ interpreter available; route check skipped' >&2
  exit 3
fi

# Force EVERY positional argument to reach check-route.py after an argparse `--`
# end-of-options marker (see header). No arg-1/arg-2 capture: `--` goes first, so a stray
# leading-dash word in ANY slot is a fail-closed arity / unrecognized-arguments error
# (exit 2), never an honoured option. The `$# -lt 3` fallback keeps `--help` / `-h` (exit 0
# usage) and the 2-arg "required: record" usage error (exit 2) identical to a bare forward.
if [ "$#" -ge 3 ]; then
  exec "$INTERP" "$PY" -- "$@"
fi
exec "$INTERP" "$PY" "$@"
