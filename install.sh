#!/usr/bin/env bash
# install.sh -- human fallback for non-plugin runtimes. Symlinks (or copies) agents/,
# skills/, commands/, and scripts/ into the target harness's config directory. Refuses to
# overwrite without --force. Resolves symlinks and handles Windows paths via cygpath.
# Fails fast if a required file is missing.
#
# scripts/ is included so agent/skill prose referencing a bundled script (e.g.
# `${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh`) has something to find at the destination. In
# --copy mode that placeholder is also resolved to a literal `$DEST` path below, so a
# copied install needs no runtime understanding of `${CLAUDE_PLUGIN_ROOT}` at all. The
# DEFAULT symlink mode cannot do that substitution without rewriting the source checkout
# through the symlink, so it is a stated, known gap: scripts/ becomes reachable, but the
# placeholder stays literal in a symlinked (non-plugin) install. Only Claude Code's own
# native `/plugin install` path (this repo's documented primary install method) resolves
# `${CLAUDE_PLUGIN_ROOT}` unconditionally, via its own plugin loader -- confirmed against
# official Claude Code docs, not assumed.
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
for d in agents skills commands scripts; do
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
  for sub in agents skills commands scripts; do
    link_one "$sub" || rc=1
  done
  # Copy mode produces independent files (unlike a symlink, which still points back at
  # the source checkout), so it is safe to rewrite the placeholder here without touching
  # the source. Applied to agents/skills/commands only -- scripts/ itself never contains
  # the placeholder, it is what the placeholder resolves to.
  #
  # NOT gated on rc -- live-caught 2026-08-19: a per-target conflict (e.g. an existing
  # skills/ from a prior run, refused without --force) set rc=1 and skipped this whole
  # pass, leaving agents/ and commands/ -- which DID copy successfully -- with the
  # placeholder unresolved even though nothing about resolving it depended on skills/
  # succeeding. The pass is idempotent (sed on an already-resolved or pre-existing file
  # is a no-op if the placeholder isn't present), so running it unconditionally in copy
  # mode is always safe, whichever subdirs actually copied this run.
  if [ "$MODE" = "copy" ]; then
    for sub in agents skills commands; do
      [ -d "$DEST/$sub" ] || continue
      find "$DEST/$sub" -type f -name '*.md' -exec sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g" {} \;
    done
    echo "resolved \${CLAUDE_PLUGIN_ROOT} -> $DEST in agents/skills/commands"
  fi
fi

if [ "$rc" -ne 0 ]; then
  echo "install.sh: completed with errors (see above)" >&2
  exit 1
fi
echo "install.sh: done. Target=$TARGET dest=$DEST mode=$MODE"
