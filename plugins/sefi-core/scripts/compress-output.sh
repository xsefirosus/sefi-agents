#!/usr/bin/env bash
# compress-output.sh <label> <cmd> [args...]
# Preserve the wrapped status while writing its output to a unique log when possible.
set -uo pipefail

LABEL="${1:-cmd}"
shift || true
TAIL_N="${SEFI_COMPRESS_TAIL_LINES:-20}"
[ "$#" -gt 0 ] || { echo "compress-output.sh: no command given" >&2; exit 2; }

LOGDIR=".worktrees/logs"
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')"
LOG=""
if mkdir -p "$LOGDIR" 2>/dev/null; then
  LOG="$(mktemp "$LOGDIR/${SAFE_LABEL}.XXXXXX.log" 2>/dev/null || true)"
fi

code=0
if [ -n "$LOG" ]; then
  "$@" >"$LOG" 2>&1 || code=$?
else
  # Logging is advisory: it never masks the command result. Avoid retaining arbitrary
  # command output in a shell variable when the requested log cannot be created.
  "$@" >/dev/null 2>&1 || code=$?
  echo "compress-output.sh: unable to create a log; diagnostics unavailable" >&2
fi

if [ "$code" -eq 0 ]; then
  printf 'ok: %s\n' "$LABEL"
  exit 0
fi

printf 'FAIL: %s (exit %s)\n' "$LABEL" "$code"
if [ -n "$LOG" ]; then
  matched="$({ grep -Ei 'error|fail|exception|assert|panic|traceback' "$LOG" | sort | uniq -c | sort -rn | head -20; } 2>/dev/null || true)"
  if [ -n "$matched" ]; then
    printf '%s\n' "$matched"
  elif [ -s "$LOG" ]; then
    printf 'no error-keyword lines; last %s lines of output:\n' "$TAIL_N"
    tail -n "$TAIL_N" "$LOG"
  else
    printf '(command produced no output)\n'
  fi
  printf 'full log: %s\n' "$LOG"
fi
exit "$code"
