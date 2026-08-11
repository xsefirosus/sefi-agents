#!/usr/bin/env bash
# apply-model-map.sh <harness> <src-dir> <dst-dir> [--map <path>]
#
# Copy agent files, rewriting each one's `model:` to the value config/model-map.yml gives
# for that agent's `tier:` on <harness>. The `tier:` line itself is dropped -- it is this
# repo's own field, not something any harness reads.
#
# For harnesses whose install path reads agent files directly with no transform step
# (Codex via the plugin marketplace; Claude Code natively). Those installers cannot rewrite
# anything, so the frontmatter has to be correct BEFORE it is read -- run this first and
# point the harness at <dst-dir>. install-opencode.sh does the same rewrite inline, as part
# of the larger tools -> permission transform it already has to do.
#
# Everything except `model:` and `tier:` is preserved byte-for-byte.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MAP=""
ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map) MAP="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    -*) echo "apply-model-map: unknown arg $1" >&2; exit 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[ "${#ARGS[@]}" -eq 3 ] || { echo "apply-model-map: usage: $0 <harness> <src-dir> <dst-dir> [--map <path>]" >&2; exit 2; }
HARNESS="${ARGS[0]}"; SRC="${ARGS[1]}"; DST="${ARGS[2]}"

[ -d "$SRC" ] || { echo "apply-model-map: source dir $SRC not found" >&2; exit 2; }
mkdir -p "$DST"

count=0
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"

  # Resolve this agent's tier through the single map reader, so every consumer of the map
  # agrees on what a tier means. A failure here is fatal rather than silent: emitting an
  # agent with no model, or with another harness's alias, is the bug this script exists to
  # prevent.
  if ! model="$(bash "$HERE/model-for.sh" --agent "$f" "$HARNESS" ${MAP:+--map "$MAP"})"; then
    echo "apply-model-map: cannot resolve a model for $base on '$HARNESS'" >&2
    exit 1
  fi

  awk -v model="$model" '
    BEGIN { in_fm = -1 }
    in_fm == -1 && /^---$/ { in_fm = 0; print; next }
    in_fm == 0  && /^---$/ { in_fm = 1; print; next }
    in_fm == 0 {
      if (/^tier:[[:space:]]*/) { next }                       # our field, not a harness field
      if (/^model:[[:space:]]*/) { print "model: " model; next }
      print; next
    }
    { print }
  ' "$f" > "$DST/$base"

  count=$((count + 1))
  printf 'mapped %-26s -> model: %s\n' "$base" "$model"
done

[ "$count" -gt 0 ] || { echo "apply-model-map: no agent files found in $SRC" >&2; exit 1; }
echo "apply-model-map: $count agent(s) written to $DST for harness '$HARNESS'"
