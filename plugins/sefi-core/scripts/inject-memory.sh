#!/usr/bin/env bash
# inject-memory.sh -- SessionStart hook. Emit a truncated memory router into context.
# Honors config/sefi.config.yml's memory.vault_dir (where the vault lives) and
# memory.inject_char_cap (the hard cap on this injection), falling back to the documented
# defaults when the config or a key is absent. Reads <vault>/index.md from the current
# project; emits nothing if it is absent. Never emits any other vault file.
set -euo pipefail

CONFIG="config/sefi.config.yml"

cfg_get() {
  # cfg_get <key> <default> -- read a leaf key's scalar from CONFIG.
  local key="$1" default="$2" val=""
  if [ -f "$CONFIG" ]; then
    val="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
  fi
  printf '%s' "${val:-$default}"
}

VAULT="$(cfg_get vault_dir memory)"
CAP="$(cfg_get inject_char_cap 1500)"
# A non-numeric cap is a config error; fall back to the default rather than failing a
# session start over it.
case "$CAP" in ''|*[!0-9]*) CAP=1500 ;; esac

INDEX="$VAULT/index.md"
[ -f "$INDEX" ] || exit 0

PREFIX="SEFI MEMORY ROUTER (truncated -- follow links via memory-protocol):"

# First 40 lines, prefixed, then the whole injection hard-capped at memory.inject_char_cap.
first40="$(head -n 40 "$INDEX")"
full="$(printf '%s\n%s' "$PREFIX" "$first40")"

printf '%s\n' "${full:0:$CAP}"
