#!/usr/bin/env bash
# sefi-harness-marker.sh <install-root> <harness-name>
#
# Write the installing harness's own name, as one line, into
# <install-root>/.sefi/harness -- the INSTALL marker that budget-check.sh reads
# relative to its own directory (../.sefi/harness) when no --harness flag and no
# $SEFI_HARNESS are set. Without it, an installed harness has no ambient identity:
# the gate falls back to the fail-closed metered default and enforces a dollar cap
# that a free or flat plan never incurs.
#
# Contract:
#   * idempotent -- writing the same name twice leaves the same one line in place;
#   * never fails the install -- a directory that cannot be created or a file that
#     cannot be written is reported once, on stderr, and the install continues;
#   * one line, one name -- the marker is a machine fact, not a log.
#
# Usage: bash sefi-harness-marker.sh <install-root> <harness-name>
set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "sefi-harness-marker: usage: sefi-harness-marker.sh <install-root> <harness-name>" >&2
  exit 2
fi

ROOT="$1"
NAME="$2"

case "$NAME" in
  opencode|hermes|codex|claude-code|cline) : ;;
  claude) NAME="claude-code" ;;
  *)
    echo "sefi-harness-marker: unknown harness '$NAME' (expected opencode, hermes, codex, claude-code, or cline)" >&2
    exit 2
    ;;
esac

[ -n "$ROOT" ] || { echo "sefi-harness-marker: install root must not be empty" >&2; exit 2; }

MARKER_DIR="$ROOT/.sefi"
MARKER="$MARKER_DIR/harness"

# Idempotence: the marker already says what this install says. Nothing to write, so
# nothing is written -- no mtime churn, no needless write on an existing install.
if [ -f "$MARKER" ]; then
  current="$(head -n1 "$MARKER" 2>/dev/null | tr -d '\r\n' | tr -d '[:space:]')"
  if [ "$current" = "$NAME" ]; then
    exit 0
  fi
fi

# The write must never fail the install. A harness home that cannot hold the marker
# is a real problem -- the installed gate will fall back to metered -- but it is not a
# reason to abort an install that otherwise succeeded. Say it once, clearly, and let
# the install finish.
if ! mkdir -p "$MARKER_DIR" 2>/dev/null; then
  echo "sefi-harness-marker: could not create $MARKER_DIR; the installed gate will fall back to the fail-closed metered default" >&2
  exit 0
fi
if ! printf '%s\n' "$NAME" > "$MARKER" 2>/dev/null; then
  echo "sefi-harness-marker: could not write $MARKER; the installed gate will fall back to the fail-closed metered default" >&2
  exit 0
fi
exit 0
