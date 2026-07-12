#!/usr/bin/env bash
# install.sh -- human fallback for non-plugin runtimes. Symlinks (or copies) agents/,
# skills/, and commands/ into the target harness's config directory. Refuses to overwrite
# without --force. Resolves symlinks and handles Windows paths via cygpath. Fails fast if a
# required file is missing.
#
# Usage: ./install.sh --target <claude|hermes|opencode> [--force] [--copy]
set -euo pipefail

TARGET=""
FORCE=0
MODE="symlink"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --copy)   MODE="copy"; shift ;;
    -h|--help) echo "usage: $0 --target <claude|hermes|opencode> [--force] [--copy]"; exit 0 ;;
    *) echo "install.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -n "$TARGET" ] || { echo "install.sh: --target is required (claude|hermes|opencode)" >&2; exit 2; }

# Resolve the plugin source root (this script's directory).
SRC="$(cd "$(dirname "$0")" && pwd)"
CORE="$SRC/plugins/sefi-core"

# Fail fast if a required source dir is missing.
for d in agents skills commands; do
  [ -d "$CORE/$d" ] || { echo "install.sh: missing required source dir $CORE/$d" >&2; exit 1; }
done

# Pick the destination base per harness.
case "$TARGET" in
  claude)   DEST="$HOME/.claude" ;;
  hermes)   DEST="${HERMES_HOME:-$HOME/.hermes}" ;;
  opencode) DEST="${OPENCODE_HOME:-$HOME/.config/opencode}" ;;
  *) echo "install.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac

# On Cygwin/MSYS, normalize a Windows-style HOME to a POSIX path.
if command -v cygpath >/dev/null 2>&1; then
  DEST="$(cygpath -u "$DEST")"
fi

mkdir -p "$DEST"

link_one() {
  # link_one <subdir>
  local sub="$1"
  local from="$CORE/$sub"
  local to="$DEST/$sub"
  if [ -e "$to" ] || [ -L "$to" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "install.sh: refusing to overwrite $to (use --force)" >&2
      return 1
    fi
    rm -rf "$to"
  fi
  if [ "$MODE" = "copy" ]; then
    cp -R "$from" "$to"
    echo "copied $sub -> $to"
  else
    ln -s "$from" "$to"
    echo "linked $sub -> $to"
  fi
}

rc=0
if [ "$TARGET" = "opencode" ]; then
  # OpenCode's `tools` field is a strictly-typed object (not a string), and the
  # agent files in this repo use a comma-separated string. A raw copy or symlink
  # fails OpenCode's schema validation. Route the opencode target through the
  # dedicated converter (agents transformed; skills + commands plain-copied).
  # install-opencode.sh accepts --force and applies it; --copy is a no-op there
  # (opencode install is always a real copy, never a symlink).
  opencode_args=()
  [ "$FORCE" -eq 1 ] && opencode_args+=(--force)
  bash "$CORE/scripts/install-opencode.sh" "${opencode_args[@]}" || rc=1
else
  for sub in agents skills commands; do
    link_one "$sub" || rc=1
  done
fi

if [ "$rc" -ne 0 ]; then
  echo "install.sh: completed with errors (see above)" >&2
  exit 1
fi
echo "install.sh: done. Target=$TARGET dest=$DEST mode=$MODE"
