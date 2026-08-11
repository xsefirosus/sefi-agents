#!/usr/bin/env bash
# compress-output.sh <label> <cmd> [args...]
# Run <cmd>; on success print "ok: <label>", on failure print deduped error lines plus a
# log pointer. Tees full output to .worktrees/logs/. Fails open: a bug in compression
# never hides the underlying result, and the wrapped command's exit code is always
# preserved. rtk-derived (no Rust).
set -euo pipefail

LABEL="${1:-cmd}"
shift || true

TAIL_N="${SEFI_COMPRESS_TAIL_LINES:-20}"

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
  matched="$({ printf '%s\n' "$out" | grep -Ei 'error|fail|exception|assert|panic|traceback' \
    | sort | uniq -c | sort -rn | head -20; } 2>/dev/null || true)"
  if [ -n "$matched" ]; then
    printf '%s\n' "$matched"
  elif [ -n "$out" ]; then
    # A tool can fail while naming none of those keywords -- "2 tests did not pass",
    # "expected 3, got 4", or a bare nonzero exit. That previously produced a FAIL line, a
    # log pointer, and ZERO diagnostics, so the one agent meant to read this (the
    # qa-engineer, re-running the gate) learned nothing without opening the log itself.
    # The tail is the cheapest non-empty fallback there is.
    printf 'no error-keyword lines; last %s lines of output:\n' "$TAIL_N"
    printf '%s\n' "$out" | tail -n "$TAIL_N"
  else
    printf '(command produced no output)\n'
  fi
  printf 'full log: %s\n' "$LOG"
fi

exit "$code"
