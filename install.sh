#!/usr/bin/env bash
# install.sh -- human fallback for non-plugin runtimes. Symlinks (or copies) agents/,
# skills/, commands/, and scripts/ into the target harness's config directory. Refuses to
# overwrite without --force. Resolves symlinks and handles Windows paths via cygpath.
# Fails fast if a required file is missing.
#
# scripts/ is included so agent/skill prose referencing a bundled script (e.g.
# `${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh`) has something to find at the destination. In
# --copy mode that placeholder is also resolved to a literal `$DEST` path in file content.
# The DEFAULT symlink mode can't do that (rewriting a symlinked file mutates the source
# checkout), so for the `claude` target specifically, `wire_claude_settings()` closes it a
# different way instead: it sets `CLAUDE_PLUGIN_ROOT` as a persistent `env` var in
# `settings.json`, which Claude Code exports to every Bash tool call -- confirmed via
# official docs, not assumed -- so the placeholder resolves via ordinary shell expansion
# with no file rewriting needed. `hermes` and `opencode` still don't get this (see that
# function's own comment for why).
#
# `wire_claude_settings()` only helps a LOCAL TERMINAL CLI install. A cloud/remote
# ("Claude Code on the web") session does not read `~/.claude/settings.json` at all,
# confirmed via official docs -- it reads a project-level `.claude/settings.json` instead,
# which this installer does not create. That's a stated scope boundary: this script's
# `claude` target was never designed for a cloud session, and doesn't claim to cover one.
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

wire_claude_settings() {
  # wire_claude_settings -- two merges into $DEST/settings.json: (1) hooks/hooks.json's own
  # "hooks" key, and (2) an "env" key setting CLAUDE_PLUGIN_ROOT to the resolved $DEST.
  # Neither this script nor install-opencode.sh ever touched hooks/ before 0.3.15 --
  # live-caught 2026-08-19: a dispatched agent with disallowedTools: Write, Edit, MultiEdit
  # ran `git commit` via Bash completely uncaught, because check-bash-write.sh (the
  # PreToolUse hook meant to block exactly that) was never registered anywhere Claude Code
  # would read it from on a fallback install. Only Claude Code's native /plugin install path
  # auto-registers a plugin's hooks.json; this restores the equivalent for install.sh's own
  # fallback claude target.
  #
  # The env half closes the symlink-mode gap 0.3.13 shipped stated-but-unsolved: a symlinked
  # (default, non-copy) install can't rewrite ${CLAUDE_PLUGIN_ROOT} in agent/skill prose
  # without mutating the source checkout, so the placeholder stayed literal. Confirmed via
  # official Claude Code docs (not assumed): settings.json's "env" key is exported to every
  # Bash tool call in a session, not just hook commands -- so a bare
  # ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh in agent/skill prose now resolves via ordinary shell
  # variable expansion, with zero file-content rewriting required. Written for both symlink
  # and copy mode; redundant in copy mode (content is already resolved there) but harmless.
  #
  # Local terminal CLI only: a cloud/remote ("Claude Code on the web") session does not
  # read ~/.claude/settings.json at all, confirmed via official docs -- it reads a
  # project-level .claude/settings.json instead, which this installer does not create. That
  # is a stated scope boundary, not silently implied-fixed.
  #
  # Hermes is deliberately NOT wired here: this repo does not know Hermes's own hook config
  # format, and inventing one would be a claim this repo cannot back -- same honesty already
  # applied to Hermes/Codex in README's check-bash-write.sh row, and already documented in
  # adapters/HERMES.md and harness-actions.md's hook-event map (UNKNOWN cells, by design).
  # OpenCode does not need this function at all: install-opencode.sh's own transform already
  # emits an equivalent bash-deny-pattern permission block per agent (see
  # emit_bash_write_gate() there), because OpenCode has no separate hooks mechanism to hang
  # this off of the way Claude Code does.
  #
  # jq-required: a hand-rolled JSON merge in sed/awk risks corrupting a real user's existing
  # settings.json (their own unrelated hooks, env, permissions, etc.). If jq is missing,
  # warn plainly and skip rather than risk it -- the same fail-open-with-honesty discipline
  # check-bash-write.sh's own resolver chain uses for a parse, applied here to a merge.
  if ! command -v jq >/dev/null 2>&1; then
    echo "install.sh: jq not found -- hooks/env NOT wired. check-bash-write.sh's" >&2
    echo "  disallowedTools enforcement, inject-memory.sh's SessionStart injection, and" >&2
    echo "  \${CLAUDE_PLUGIN_ROOT} resolution in a symlinked install will not work. Install" >&2
    echo "  jq and re-run, or merge $CORE/hooks/hooks.json into $DEST/settings.json by hand" >&2
    echo "  (resolve \${CLAUDE_PLUGIN_ROOT} -> $DEST first) and add" >&2
    echo "  \"env\": {\"CLAUDE_PLUGIN_ROOT\": \"$DEST\"}." >&2
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
  jq --argjson new "$(printf '%s' "$resolved" | jq '.hooks')" \
     --arg plugin_root "$DEST" '
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
    | .env = ((.env // {}) + {CLAUDE_PLUGIN_ROOT: $plugin_root})
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "wired hooks/hooks.json -> $settings (SessionStart + PreToolUse:Bash), env.CLAUDE_PLUGIN_ROOT=$DEST"
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
  [ "$TARGET" = "claude" ] && wire_claude_settings
fi

if [ "$rc" -ne 0 ]; then
  echo "install.sh: completed with errors (see above)" >&2
  exit 1
fi
echo "install.sh: done. Target=$TARGET dest=$DEST mode=$MODE"
