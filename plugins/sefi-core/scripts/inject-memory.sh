#!/usr/bin/env bash
# inject-memory.sh -- SessionStart hook. Emit a truncated memory router into context.
# Reads memory/index.md from the current project; emits nothing if it is absent.
# Never emits any other vault file.
set -euo pipefail

INDEX="memory/index.md"
[ -f "$INDEX" ] || exit 0

PREFIX="SEFI MEMORY ROUTER (truncated -- follow links via memory-protocol):"

# First 40 lines, prefixed, then the whole injection hard-capped at 1500 characters.
first40="$(head -n 40 "$INDEX")"
full="$(printf '%s\n%s' "$PREFIX" "$first40")"

printf '%s\n' "${full:0:1500}"
