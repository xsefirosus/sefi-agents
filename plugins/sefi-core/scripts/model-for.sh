#!/usr/bin/env bash
# model-for.sh <harness> <tier> [--reasoning] [--map <path>]
# model-for.sh --agent <agent-file> <harness> [--map <path>]
#
# Resolve a harness-neutral tier to that harness's concrete model identifier, from
# config/model-map.yml. The single reader of the map, so every installer and validator
# resolves a tier the same way rather than each parsing YAML its own way.
#
# Pure POSIX awk -- no yq, no python, nothing to install. The map is a fixed two-level
# shape (harness, then tier), which is exactly what that buys.
#
# Exits 1 with a message on an unknown harness or an unmapped tier. A silent empty result
# would let an installer emit `model:` with no value, which is worse than a bare alias.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MAP="$HERE/../config/model-map.yml"
AGENT=""
HARNESS=""
TIER=""

FIELD="model"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map)   MAP="${2:-}"; shift 2 ;;
    --agent) AGENT="${2:-}"; shift 2 ;;
    --reasoning) FIELD="reasoning"; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    -*) echo "model-for: unknown arg $1" >&2; exit 2 ;;
    *)
      if [ -z "$HARNESS" ]; then HARNESS="$1"
      elif [ -z "$TIER" ]; then TIER="$1"
      else echo "model-for: unexpected arg $1" >&2; exit 2
      fi
      shift ;;
  esac
done

[ -f "$MAP" ] || { echo "model-for: model map not found at $MAP" >&2; exit 1; }

if [ -n "$AGENT" ]; then
  [ -f "$AGENT" ] || { echo "model-for: agent file $AGENT not found" >&2; exit 1; }
  TIER="$(awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$AGENT" \
    | sed -n 's/^tier:[[:space:]]*\([a-z]*\).*/\1/p' | head -1)"
  [ -n "$TIER" ] || { echo "model-for: $AGENT declares no 'tier:' line" >&2; exit 1; }
fi

[ -n "$HARNESS" ] || { echo "model-for: usage: model-for.sh <harness> <tier>" >&2; exit 2; }
[ -n "$TIER" ]    || { echo "model-for: usage: model-for.sh <harness> <tier>" >&2; exit 2; }

# --reasoning reads `<tier>_reasoning`; the default reads the bare `<tier>` key.
lookup="$TIER"
[ "$FIELD" = "reasoning" ] && lookup="${TIER}_reasoning"

result="$(awk -v h="$HARNESS" -v t="$lookup" '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  /^[a-z][a-z0-9-]*:[[:space:]]*$/ {
    block = $1; sub(/:$/, "", block)
    inblock = (block == h)
    next
  }
  inblock && /^[[:space:]]+[a-z_]+:[[:space:]]*[^[:space:]]/ {
    key = $1; sub(/:$/, "", key)
    if (key == t) { print $2; exit }
  }
' "$MAP")"

if [ -z "$result" ]; then
  known="$(awk '/^[a-z][a-z0-9-]*:[[:space:]]*$/ { k=$1; sub(/:$/,"",k); printf "%s ", k }' "$MAP")"
  echo "model-for: no $FIELD for harness='$HARNESS' tier='$TIER' (key '$lookup') in $MAP (known harnesses: $known)" >&2
  exit 1
fi

printf '%s\n' "$result"
