#!/usr/bin/env bash
# compress-output.sh <label> <cmd> [args...]
# Run <cmd>; on success print "ok: <label>", on failure print deduped error lines plus a
# log pointer. Tees full output to .worktrees/logs/. Fails open: a bug in compression
# never hides the underlying result, and the wrapped command's exit code is always
# preserved. rtk-derived (no Rust).
set -euo pipefail

LABEL="${1:-cmd}"
shift || true

if [ "$#" -eq 0 ]; then
  echo "compress-output.sh: no command given" >&2
  exit 2
fi

LOGDIR=".worktrees/logs"
mkdir -p "$LOGDIR" 2>/dev/null || true
TS="$(date +%Y%m%d-%H%M%S)"
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')"
LOG="${LOGDIR}/${TS}_${SAFE_LABEL}.log"

# Run the command; capture combined output and its exit code without aborting.
code=0
out="$("$@" 2>&1)" || code=$?

# Tee the full output to the log (best-effort; fail open).
printf '%s\n' "$out" > "$LOG" 2>/dev/null || true

if [ "$code" -eq 0 ]; then
  printf 'ok: %s\n' "$LABEL"
else
  printf 'FAIL: %s (exit %s)\n' "$LABEL" "$code"
  # failure-focused, deduped lines (fail open on any compressor error)
  { printf '%s\n' "$out" | grep -Ei 'error|fail|exception' | sort | uniq -c | sort -rn | head -20; } || true
  printf 'full log: %s\n' "$LOG"
fi

exit "$code"
