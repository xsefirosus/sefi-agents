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

BEGIN="<!-- GENERATED:router -->"
END="<!-- /GENERATED:router -->"

# Inject the GENERATED:router block, not the head of the file. Everything above that block
# in a real index.md -- frontmatter, title, the folder list, the "do not hand-edit" note --
# is static boilerplate the model gains nothing from re-reading every session. The previous
# `head -n 40` spent roughly half its window on it (the block starts at line 21 of the
# shipped template) and truncated the routing lines that carry the only actual signal.
# gen-router.sh already orders notes so that truncation drops trace notes before decisions;
# that ordering only pays off once the window is spent on router lines in the first place.
body=""
if grep -qF "$BEGIN" "$INDEX" && grep -qF "$END" "$INDEX"; then
  body="$(awk -v b="$BEGIN" -v e="$END" '
    $0==b { f=1; next }
    $0==e { f=0 }
    f && $0 !~ /^<!--/ { print }
  ' "$INDEX")"
  if [ -z "$body" ]; then
    # Initialized but empty. Say so in one line: it tells the session a vault exists and is
    # writable here, which is the whole cue for filing anything into it.
    printf '%s\n' "SEFI MEMORY: vault at $VAULT/ is initialized but empty (no notes filed yet)."
    exit 0
  fi
else
  # No markers: a hand-written index.md. Fall back to the old window rather than emitting
  # nothing -- some router is better than none.
  body="$(head -n 40 "$INDEX")"
fi

# Prefixed, then the whole injection hard-capped at memory.inject_char_cap.
full="$(printf '%s\n%s' "$PREFIX" "$body")"

printf '%s\n' "${full:0:$CAP}"
