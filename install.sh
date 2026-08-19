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

wire_hooks_claude() {
  # wire_hooks_claude -- merge plugins/sefi-core/hooks/hooks.json into $DEST/settings.json's
  # own "hooks" key. Neither this script nor install-opencode.sh ever touched hooks/ before
  # this, at all -- live-caught 2026-08-19: a dispatched agent with
  # disallowedTools: Write, Edit, MultiEdit ran `git commit` via Bash completely uncaught,
  # because check-bash-write.sh (the PreToolUse hook meant to block exactly that) was never
  # registered anywhere Claude Code would read it from on a fallback install. Only Claude
  # Code's native /plugin install path auto-registers a plugin's hooks.json; this restores
  # the equivalent for install.sh's own fallback claude target.
  #
  # Hermes is deliberately NOT wired here: this repo does not know Hermes's own hook config
  # format, and inventing one would be a claim this repo cannot back -- same honesty already
  # applied to Hermes/Codex in README's check-bash-write.sh row. OpenCode does not need this
  # function at all: install-opencode.sh's own transform already emits an equivalent
  # bash-deny-pattern permission block per agent (see emit_bash_write_gate() there), because
  # OpenCode has no separate hooks mechanism to hang this off of the way Claude Code does.
  #
  # jq-required: a hand-rolled JSON merge in sed/awk risks corrupting a real user's existing
  # settings.json (their own unrelated hooks, permissions, etc.). If jq is missing, warn
  # plainly and skip rather than risk it -- the same fail-open-with-honesty discipline
  # check-bash-write.sh's own resolver chain uses for a parse, applied here to a merge.
  if ! command -v jq >/dev/null 2>&1; then
    echo "install.sh: jq not found -- hooks NOT wired. check-bash-write.sh's disallowedTools" >&2
    echo "  enforcement and inject-memory.sh's SessionStart injection will not run for this" >&2
    echo "  install. Install jq and re-run, or merge $CORE/hooks/hooks.json into" >&2
    echo "  $DEST/settings.json by hand (resolve \${CLAUDE_PLUGIN_ROOT} -> $DEST first)." >&2
    return 0
  fi
  local hooks_src="$CORE/hooks/hooks.json"
  if [ ! -f "$hooks_src" ]; then
    echo "install.sh: $hooks_src not found -- hooks not wired" >&2
    return 0
  fi

  local resolved settings tmp
  resolved="$(sed "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g" "$hooks_src")"
  settings="$DEST/settings.json"
  [ -f "$settings" ] || echo '{}' > "$settings"

  tmp="$(mktemp)"
  jq --argjson new "$(printf '%s' "$resolved" | jq '.hooks')" '
    .hooks = (
      (.hooks // {}) as $existing |
      ($new | keys) as $events |
      reduce $events[] as $ev
        ($existing;
          .[$ev] = (
            (.[$ev] // []) as $cur |
            ($new[$ev] // []) as $add |
            $cur + [ $add[] | select(. as $item | ($cur | index($item)) == null) ]
          )
        )
    )
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "wired hooks/hooks.json -> $settings (SessionStart + PreToolUse:Bash)"
}

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
  # Hook wiring is independent of MODE (it edits settings.json, not the copied/symlinked
  # agent files) and independent of rc for the same reason as the substitution pass above:
  # a skills/ conflict has nothing to do with whether hooks should be wired.
  [ "$TARGET" = "claude" ] && wire_hooks_claude
fi

if [ "$rc" -ne 0 ]; then
  echo "install.sh: completed with errors (see above)" >&2
  exit 1
fi
echo "install.sh: done. Target=$TARGET dest=$DEST mode=$MODE"
