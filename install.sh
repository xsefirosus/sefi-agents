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
# Usage: ./install.sh --target <adapter-id> | --adapter <manifest-path> [--model-map <path>] [--force] [--copy]
set -euo pipefail

TARGET=""
ADAPTER=""
MODEL_MAP=""
FORCE=0
MODE="symlink"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --adapter) ADAPTER="${2:-}"; shift 2 ;;
    --model-map) MODEL_MAP="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --copy)   MODE="copy"; shift ;;
    -h|--help) echo "usage: $0 (--target <adapter-id> | --adapter <manifest-path>) [--model-map <path>] [--force] [--copy]"; exit 0 ;;
    *) echo "install.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] || [ -z "$ADAPTER" ] || { echo "install.sh: use either --target or --adapter, not both" >&2; exit 2; }
[ -n "$TARGET$ADAPTER" ] || { echo "install.sh: --target or --adapter is required" >&2; exit 2; }

# Resolve the plugin source root (this script's directory).
SRC="$(cd "$(dirname "$0")" && pwd)"
CORE="$SRC/plugins/sefi-core"
MANIFEST_HELPER="$CORE/scripts/adapter-manifest.sh"
[ -f "$MANIFEST_HELPER" ] || { echo "install.sh: adapter manifest driver is missing" >&2; exit 1; }
# shellcheck source=plugins/sefi-core/scripts/adapter-manifest.sh
source "$MANIFEST_HELPER"

if [ -n "$TARGET" ]; then
  [ "$TARGET" = "claude" ] && TARGET="claude-code"
  ADAPTER="$SRC/adapters/manifests/$TARGET.yml"
fi
adapter_manifest_load "$ADAPTER" || exit 2

if [ -z "$TARGET" ] && [ "$ADAPTER_SUPPORT" != "custom" ]; then
  echo "install.sh: --adapter accepts only locally usable custom manifests" >&2
  exit 2
fi

TARGET="$ADAPTER_ID"

if [ -n "$MODEL_MAP" ] && [ ! -f "$MODEL_MAP" ]; then
  echo "install.sh: model map not found at $MODEL_MAP" >&2
  exit 2
fi

if [ "$ADAPTER_DRIVER" = "codex-bootstrap" ]; then
  [ "$FORCE" -eq 0 ] && [ "$MODE" = "symlink" ] || {
    echo "install.sh: --force and --copy do not apply to the Codex bootstrap" >&2
    exit 2
  }
  codex_args=()
  [ -n "$MODEL_MAP" ] && codex_args+=(--model-map "$MODEL_MAP")
  exec bash "$SRC/install-codex.sh" "${codex_args[@]}"
fi

# Fail fast if a required source dir is missing.
for d in agents skills commands scripts; do
  [ -d "$CORE/$d" ] || { echo "install.sh: missing required source dir $CORE/$d" >&2; exit 1; }
done

# Resolve the manifest's portable ${HOME}/... destination. Preserve the historic
# environment overrides for the two fallback filesystem harnesses.
DEST="$HOME/${ADAPTER_DESTINATION#\$\{HOME\}/}"
if [ "$TARGET" = "hermes" ] && [ -n "${HERMES_HOME:-}" ]; then DEST="$HERMES_HOME"; fi

# On Cygwin/MSYS, normalize a Windows-style HOME to a POSIX path.
if command -v cygpath >/dev/null 2>&1; then
  DEST="$(cygpath -u "$DEST")"
fi

sefi_normalize_path() {
  # sefi_normalize_path <path> -- absolutize <path> and lexically collapse
  # duplicate slashes, dot components, and dot-dot components (clamped at the
  # root), stripping trailing slashes, so a spelled path can be compared byte
  # for byte against its physical location below. Returns non-zero and prints
  # nothing for input no POSIX layer can interpret: a backslash anywhere, or a
  # drive-letter prefix.
  #
  # That refusal is deliberate fail-closed portability, not an oversight. Every
  # installer already runs a Windows-style path through cygpath -u at its entry
  # point, so a backslash or drive letter that survives to here is input nothing
  # normalized. Read as a path it is ONE legal relative component -- "C:\Users\me"
  # is a valid directory name -- and mkdir -p would create it under $PWD rather
  # than installing anywhere the caller named. Refusing costs a caller who typed
  # the wrong form one clear message; guessing costs them a silent install in a
  # directory they never asked for.
  #
  # sefi: this helper and sefi_canonical_path are triplicated per installer
  # instead of sourced from one file, because install.sh and install-codex.sh
  # must keep working from a checkout whose plugin tree is not installed yet.
  # Ceiling: a fix applied to one copy can drift from the other two. Upgrade
  # path: the installer suite asserts the three copies are byte-identical, so
  # drift fails there; the real fix is one shared sourced helper, deferred until
  # the bootstrap can guarantee that file is present.
  local path="$1" rest="" piece="" result="" stripped=""
  case "$path" in
    # Empty input normalized to $PWD, which would hand the caller the working directory
    # as a destination nobody named. No installer can reach it today -- every entry
    # point substitutes a default for an empty variable -- so this is a pinned
    # invariant, not a reachable bug.
    "") return 1 ;;
    *\\*) return 1 ;;
    [A-Za-z]:*) return 1 ;;
    /*)
      # Strip EVERY leading slash, not just the first. "//C:/x" and "///C:/x" spell
      # the same MSYS-style drive path as "/C:/x", but a one-slash strip leaves a
      # separator in front of the drive letter, the case below matches nothing, and
      # the drive-letter path sails through to be folded in as one relative
      # component -- the exact failure this refusal exists to prevent.
      stripped="$path"
      while [ "${stripped#/}" != "$stripped" ]; do stripped="${stripped#/}"; done
      case "$stripped" in [A-Za-z]:*) return 1 ;; esac
      ;;
  esac
  case "$path" in /*) : ;; *) path="$PWD/$path" ;; esac
  rest="$path"
  while [ -n "$rest" ]; do
    piece="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$piece" in
      ""|.) continue ;;
      ..) result="${result%/*}" ;;
      *) result="$result/$piece" ;;
    esac
  done
  [ -n "$result" ] || result="/"
  printf '%s' "$result"
}

sefi_canonical_path() {
  # sefi_canonical_path <path> -- print the physical location of <path>,
  # resolving every symlink component. A non-existent leaf is handled by fully
  # canonicalizing the nearest existing ancestor with cd -P/pwd -P (not a bare
  # -L test on it) and reattaching the remainder. Fails when no physical
  # directory location can be established, or when <path> is not a POSIX path.
  #
  # The two halves of that result are spelled differently, so they are normalized
  # back together rather than concatenated raw: `pwd -P` prints the filesystem
  # root as "/", and the remainder carries its own leading separator, so a plain
  # concatenation against a root ancestor prints "//a/b". The refusal check below
  # compares this value against the spelled path byte for byte, so a doubled
  # separator is not cosmetic -- it would refuse a legitimate destination whose
  # nearest existing ancestor is the root. Reusing sefi_normalize_path keeps one
  # definition of the canonical spelling instead of a second hand-rolled slash
  # fixup that can drift from the first.
  local probe="$1" parent="" remainder="" phys=""
  probe="$(sefi_normalize_path "$probe")" || return 1
  while [ ! -e "$probe" ] && [ ! -L "$probe" ]; do
    parent="$(dirname "$probe")"
    [ "$parent" != "$probe" ] || break
    remainder="/$(basename "$probe")$remainder"
    probe="$parent"
  done
  [ -d "$probe" ] || return 1
  phys="$(cd -P "$probe" 2>/dev/null && pwd -P)" || return 1
  sefi_normalize_path "$phys$remainder"
}

sefi_inside_or_equal() {
  # sefi_inside_or_equal <candidate> <root> -- succeed when <candidate> equals
  # <root> or sits inside it. A literal prefix comparison (no glob), so parent
  # directories containing glob characters cannot confuse the test. A root of
  # "/" only ever matches itself.
  local candidate="$1" root="$2"
  [ -n "$candidate" ] && [ -n "$root" ] || return 1
  [ "$candidate" = "$root" ] && return 0
  [ "$root" = "/" ] && return 1
  [ "${candidate:0:${#root}}" = "$root" ] || return 1
  [ "${candidate:${#root}:1}" = "/" ] || return 1
  return 0
}

sefi_assert_write_target() {
  # sefi_assert_write_target <target> <root> <label> -- re-verify at the write site
  # itself that <target> still resolves inside <root>.
  #
  # The directory gate below runs once, before any write. Anyone with write access to
  # a parent directory can swap an already-verified directory for a symlink in the
  # window between that gate and the write, and every later write then lands wherever
  # the symlink points -- a directory gate alone is a check-then-act race. Re-resolving
  # the exact path being written, immediately before the write, closes the window for
  # the whole install: a directory swapped mid-run is caught by the next write site
  # instead of being followed. Callers pass the path they are about to write (not just
  # DEST), because the subtree is the thing that gets swapped.
  #
  # sefi: this constrains SYMLINKED DESTINATIONS only. It does not and cannot
  # constrain an arbitrary spelling a caller passed in -- a caller who names a
  # legitimate in-tree path, or one reachable only through a symlink it controls
  # above <root>, has already satisfied the gate, and this is not a sanitiser for
  # caller-supplied path text. Ceiling: a re-check still leaves a sub-millisecond
  # window between this test and the following write, because POSIX shell offers no
  # way to open a directory handle once and write relative to it. Upgrade path: route
  # the staged writes through the interpreter this repo already requires
  # (install-codex.sh's $PYTHON_BIN, or a small os.open(..., O_NOFOLLOW) helper) so
  # the containment decision and the write share one file descriptor.
  local target_phys="" root_phys="" parent_phys=""
  # Resolve the directory that will actually receive the bytes. An existing directory
  # (including one reached through a symlink) is canonicalized directly, which is what
  # catches a swapped subtree. Anything else is resolved through its parent directory
  # and the leaf reattached, because sefi_canonical_path is defined over directories
  # and would refuse a regular file it was handed.
  if [ -d "$1" ]; then
    target_phys="$(sefi_canonical_path "$1")" || {
      echo "$3: refusing write target with no physical location: $1" >&2
      return 1
    }
  else
    parent_phys="$(sefi_canonical_path "$(dirname "$1")")" || {
      echo "$3: refusing write target with no physical parent directory: $1" >&2
      return 1
    }
    target_phys="$parent_phys/$(basename "$1")"
  fi
  root_phys="$(sefi_canonical_path "$2")" || {
    echo "$3: refusing to write because the install root has no physical location: $2" >&2
    return 1
  }
  sefi_inside_or_equal "$target_phys" "$root_phys" || {
    echo "$3: refusing write target escaping the install root: $1 resolves to $target_phys" >&2
    return 1
  }
  return 0
}

refuse_escaped_dest() {
  # refuse_escaped_dest -- refuse when DEST resolves outside its expected
  # location. DEST is normalized (trailing slashes stripped, so a trailing
  # slash cannot blind the checks) and resolved to its physical location,
  # canonicalizing the nearest existing ancestor fully instead of testing -L
  # on it, so an existing victim/subdir reached through a symlinked parent
  # cannot slip through. The physical DEST must equal the spelled DEST (no
  # symlink hop anywhere in the chain) or sit inside the canonical HOME tree
  # (which tolerates a user-managed in-HOME layout such as a dotfiles
  # symlink); anything else is an escape and the install stops before mkdir
  # -p can follow it. Input the normalizer refuses is fatal here rather than
  # silently becoming the empty string, which would otherwise sail through the
  # comparisons below and hand mkdir -p an unverified destination.
  #
  # Scope: this gate constrains SYMLINKED DESTINATIONS only, not arbitrary caller
  # spellings. A caller who passes a legitimate in-tree path (or one that resolves
  # into HOME through a symlink the user themself manages) is accepted by design; the
  # check is not a sanitiser for caller-supplied path text.
  local normalized_dest=""
  normalized_dest="$(sefi_normalize_path "$DEST")" || {
    echo "install.sh: refusing destination that is not a POSIX path: $DEST" >&2
    return 1
  }
  DEST="$normalized_dest"
  DEST_PHYS="$(sefi_canonical_path "$DEST")" || {
    echo "install.sh: refusing destination with no physical location: $DEST" >&2
    return 1
  }
  HOME_PHYS="$(sefi_canonical_path "$HOME")" || HOME_PHYS=""
  if [ "$DEST_PHYS" != "$DEST" ] && ! sefi_inside_or_equal "$DEST_PHYS" "$HOME_PHYS"; then
    echo "install.sh: refusing destination escaping its expected root: $DEST resolves to $DEST_PHYS" >&2
    return 1
  fi
}
refuse_escaped_dest || exit 1
mkdir -p "$DEST"
[ -d "$DEST" ] || {
  echo "install.sh: refusing non-directory destination $DEST" >&2
  exit 1
}
refuse_escaped_dest || exit 1
# Escape DEST for use as a sed replacement with the # delimiter: the backslash
# first (it is the escape character), then & (the whole-match placeholder),
# then # (this expression's delimiter), then newline (a raw newline would end
# the sed command, so it becomes a backslash-escaped newline instead). Pure
# bash expansions, so no sed dialect can misread a multi-line replacement.
ESCAPED_DEST="${DEST//\\/\\\\}"
ESCAPED_DEST="${ESCAPED_DEST//&/\\&}"
ESCAPED_DEST="${ESCAPED_DEST//#/\\#}"
ESCAPED_DEST="${ESCAPED_DEST//$'\n'/$'\\\n'}"

PACKAGE_MANIFEST="$CORE/scripts/package-manifest.sh"
LEGACY_KNOWLEDGE_MANAGER="$DEST/agents/knowledge-manager.md"
LEGACY_KNOWLEDGE_MANAGER_BACKUP=""

is_sefi_managed_file() {
  # is_sefi_managed_file <path> -- a legacy profile is Sefi-owned only when its source
  # file says so. A same-named user profile must survive a forced package refresh.
  [ -f "$1" ] && grep -q '^[[:space:]]*managed-by:[[:space:]]*sefi-agents[[:space:]]*$' "$1"
}

prepare_legacy_knowledge_manager() {
  # v0.8 no longer ships knowledge-manager.md. Before a forced directory replacement,
  # remove the old profile only when it declares Sefi ownership; temporarily move a
  # user-owned same-named file so the replacement cannot erase it.
  [ -e "$LEGACY_KNOWLEDGE_MANAGER" ] || [ -L "$LEGACY_KNOWLEDGE_MANAGER" ] || return 0
  if is_sefi_managed_file "$LEGACY_KNOWLEDGE_MANAGER"; then
    if [ ! -f "$CORE/agents/knowledge-manager.md" ]; then
      rm -f -- "$LEGACY_KNOWLEDGE_MANAGER"
      echo "install.sh: removed managed legacy knowledge-manager profile"
    fi
    return 0
  fi

  refuse_escaped_dest || return 1
  sefi_assert_write_target "$LEGACY_KNOWLEDGE_MANAGER" "$DEST" \
    "install.sh: refusing to move $LEGACY_KNOWLEDGE_MANAGER" || return 1
  LEGACY_KNOWLEDGE_MANAGER_BACKUP="$(mktemp "$DEST/.sefi-legacy-knowledge-manager.XXXXXX")"
  rm -f -- "$LEGACY_KNOWLEDGE_MANAGER_BACKUP"
  mv -- "$LEGACY_KNOWLEDGE_MANAGER" "$LEGACY_KNOWLEDGE_MANAGER_BACKUP"
  echo "install.sh: preserving user-owned legacy knowledge-manager profile"
}

restore_legacy_knowledge_manager() {
  local restored_phys="" parent_phys=""
  [ -n "$LEGACY_KNOWLEDGE_MANAGER_BACKUP" ] || return 0
  [ -e "$LEGACY_KNOWLEDGE_MANAGER_BACKUP" ] || return 0
  # The restore runs from an EXIT trap, so it must not depend on a caller-owned
  # invariant still holding. Re-resolve both ends before touching the destination: a
  # directory swapped since prepare_ would otherwise redirect the mkdir below and the
  # move that follows it. The containment decision comes FIRST because the mkdir is
  # itself a write -- creating the parent through a symlink is the escape, so refusing
  # only after the directory already exists is refusing one step too late.
  refuse_escaped_dest || return 0
  parent_phys="$(sefi_canonical_path "$(dirname "$LEGACY_KNOWLEDGE_MANAGER")")" || return 0
  sefi_inside_or_equal "$parent_phys" "$DEST_PHYS" || {
    echo "install.sh: refusing to create $(dirname "$LEGACY_KNOWLEDGE_MANAGER") for the legacy knowledge-manager restore (resolves to $parent_phys); preserved at $LEGACY_KNOWLEDGE_MANAGER_BACKUP" >&2
    return 0
  }
  mkdir -p "$parent_phys"
  if [ -e "$LEGACY_KNOWLEDGE_MANAGER" ] || [ -L "$LEGACY_KNOWLEDGE_MANAGER" ]; then
    echo "install.sh: preserved user-owned legacy knowledge-manager at $LEGACY_KNOWLEDGE_MANAGER_BACKUP; destination remained occupied" >&2
    return 0
  fi
  # Re-verify again after the mkdir, immediately before moving the user's own file back.
  refuse_escaped_dest || return 0
  restored_phys="$(sefi_canonical_path "$LEGACY_KNOWLEDGE_MANAGER")" || return 0
  sefi_inside_or_equal "$restored_phys" "$DEST_PHYS" || {
    echo "install.sh: refusing to restore legacy knowledge-manager outside $DEST (resolves to $restored_phys); preserved at $LEGACY_KNOWLEDGE_MANAGER_BACKUP" >&2
    return 0
  }
  mv -- "$LEGACY_KNOWLEDGE_MANAGER_BACKUP" "$LEGACY_KNOWLEDGE_MANAGER"
}

finish_legacy_knowledge_manager() {
  local status="$?"
  restore_legacy_knowledge_manager
  exit "$status"
}
trap finish_legacy_knowledge_manager EXIT

write_package_manifest() {
  # write_package_manifest <source-dir> <destination-dir>. Only a copied directory gets
  # a manifest; a symlink would write into the source checkout, and transformed agents do
  # not have byte-identical canonical sources. Preserve an unrelated manifest file.
  local source_dir="$1" destination_dir="$2" manifest="$2/.sefi-agents-manifest.json"
  [ -f "$PACKAGE_MANIFEST" ] || {
    echo "install.sh: package manifest helper missing; copied $destination_dir has no manifest" >&2
    return 0
  }
  if [ -e "$manifest" ] && ! grep -q '"format"[[:space:]]*:[[:space:]]*"sefi-package-manifest/v1"' "$manifest" 2>/dev/null; then
    echo "install.sh: preserving existing user-owned package manifest at $manifest" >&2
    return 0
  fi
  # Re-verify at the write site: the helper below writes into $destination_dir, so a
  # scripts/ subtree swapped for a symlink since the directory gate would otherwise be
  # followed straight into it.
  refuse_escaped_dest || return 1
  sefi_assert_write_target "$destination_dir" "$DEST" \
    "install.sh: refusing to write a manifest into $destination_dir" || return 1
  bash "$PACKAGE_MANIFEST" create --root "$DEST" --source "$source_dir" --destination "$destination_dir"
  echo "install.sh: wrote package manifest at $manifest"
}

print_onboarding() {
  cat <<'EOF'
sefi-agents: installation succeeded.
sefi-agents: run /sefi:init once from each project root before the first routed request.
sefi-agents: auto-init is unsafe because installation is user-wide and cannot safely choose or modify a project.
sefi-agents: cross-project memory is optional, local/private, and off by default; /sefi:init asks interactively and keeps it off when unattended.
EOF
}

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

  local resolved settings tmp settings_new
  resolved="$(sed "s#\${CLAUDE_PLUGIN_ROOT}#$ESCAPED_DEST#g" "$hooks_src")"
  settings="$DEST/settings.json"
  # Re-verify at the write site: every staging temp below is created inside $DEST, so
  # a DEST swapped for a symlink since the directory gate would receive those bytes.
  refuse_escaped_dest || exit 1
  sefi_assert_write_target "$DEST" "$HOME_PHYS" \
    "install.sh: refusing to wire settings into $DEST" || exit 1
  sefi_assert_write_target "$settings" "$DEST" \
    "install.sh: refusing to wire settings into $settings" || exit 1
  [ ! -L "$settings" ] || {
    echo "install.sh: refusing symlinked settings file $settings" >&2
    exit 1
  }
  if [ ! -e "$settings" ]; then
    # Create through a staged temp file moved into place, never a direct
    # redirect at the live path, so a symlink swapped in after the check above
    # cannot divert the creation write into another file.
    settings_new="$(mktemp "$DEST/.sefi-settings.XXXXXX")" || exit 1
    printf '{}\n' > "$settings_new"
    if [ -e "$settings" ] || [ -L "$settings" ]; then
      rm -f "$settings_new"
    else
      mv -n "$settings_new" "$settings" || {
        rm -f "$settings_new"
        echo "install.sh: cannot create settings file $settings" >&2
        exit 1
      }
      rm -f "$settings_new"
    fi
  fi
  [ ! -L "$settings" ] || {
    echo "install.sh: refusing symlinked settings file $settings" >&2
    exit 1
  }
  [ -f "$settings" ] || {
    echo "install.sh: settings file unavailable at $settings" >&2
    exit 1
  }

  tmp="$(mktemp "$DEST/.sefi-settings-merge.XXXXXX")" || exit 1
  # The merge reads the live settings.json and replaces it, so re-resolve both the
  # directory and the file immediately before the read, not only at the top of this
  # function -- the jq merge above already took time inside it.
  refuse_escaped_dest || { rm -f "$tmp"; exit 1; }
  sefi_assert_write_target "$settings" "$DEST" \
    "install.sh: refusing to merge hooks into $settings" || { rm -f "$tmp"; exit 1; }
  [ ! -L "$settings" ] || {
    rm -f "$tmp"
    echo "install.sh: refusing symlinked settings file $settings" >&2
    exit 1
  }
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
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" || {
    rm -f "$tmp"
    echo "install.sh: cannot merge hooks into $settings" >&2
    exit 1
  }
  echo "wired hooks/hooks.json -> $settings (SessionStart + PreToolUse:Bash), env.CLAUDE_PLUGIN_ROOT=$DEST"
}

link_one() {
  # link_one <subdir>
  local sub="$1"
  local from="$CORE/$sub"
  local to="$DEST/$sub"
  # Re-verify both the install root and this exact subtree immediately before any
  # destructive step. link_one runs once per subdir, so each rm -rf/cp/ln is preceded
  # by a fresh resolution of the path it is about to touch.
  refuse_escaped_dest || return 1
  sefi_assert_write_target "$to" "$DEST" "install.sh: refusing to write $to" || return 1
  if [ -e "$to" ] || [ -L "$to" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "install.sh: refusing to overwrite $to (use --force)" >&2
      return 1
    fi
    rm -rf "$to"
  fi
  # Second re-check, after the rm -rf: that removal is exactly the window an attacker
  # with write access to DEST can use to swap the subtree for a symlink, so the
  # containment of the path about to receive bytes is resolved again here.
  sefi_assert_write_target "$to" "$DEST" "install.sh: refusing to write $to" || return 1
  if [ "$MODE" = "copy" ]; then
    cp -R "$from" "$to"
    echo "copied $sub -> $to"
  else
    ln -s "$from" "$to"
    echo "linked $sub -> $to"
  fi
}

preflight_filesystem_destinations() {
  # Check every subtree before replacing any. This prevents a late no-force conflict from
  # leaving an earlier agents/, skills/, or commands/ subtree as a partial installation.
  local sub target
  [ "$FORCE" -eq 1 ] && return 0
  for sub in "$@"; do
    target="$DEST/$sub"
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "install.sh: refusing to overwrite $target (use --force)" >&2
      return 1
    fi
  done
}

materialize_mapped_agents() {
  # Canonical agents deliberately carry only a harness-neutral tier. A filesystem adapter
  # that declares model_strategy: mapped must therefore generate real agent files rather
  # than symlinking the canonical sources, otherwise --model-map would be accepted but inert.
  local target="$DEST/agents"
  local staging map_args=()
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "install.sh: refusing to overwrite $target (use --force)" >&2
      return 1
    fi
  fi
  refuse_escaped_dest || return 1
  sefi_assert_write_target "$target" "$DEST" "install.sh: refusing to generate agents into $target" || return 1
  staging="$(mktemp -d "$DEST/.sefi-agents.XXXXXX")" || return 1
  [ -n "$MODEL_MAP" ] && map_args+=(--map "$MODEL_MAP")
  if ! bash "$CORE/scripts/apply-model-map.sh" "$TARGET" "$CORE/agents" "$staging/agents" "${map_args[@]}"; then
    rm -rf "$staging"
    return 1
  fi
  # Re-verify after generation and immediately before the swap, not just at the gate:
  # generation is the longest step in this function, so it is the widest window for a
  # subtree swap, and the mv below would otherwise carry the staged bytes straight
  # through it.
  refuse_escaped_dest || { rm -rf "$staging"; return 1; }
  sefi_assert_write_target "$target" "$DEST" "install.sh: refusing to generate agents into $target" || {
    rm -rf "$staging"
    return 1
  }
  if [ -e "$target" ] || [ -L "$target" ]; then rm -rf "$target"; fi
  mv "$staging/agents" "$target"
  rmdir "$staging"
  echo "generated mapped agents -> $target"
}

rc=0
if [ "$ADAPTER_DRIVER" = "opencode-native" ]; then
  # OpenCode's `tools` field is a strictly-typed object (not a string), and the
  # agent files in this repo use a comma-separated string. A raw copy or symlink
  # fails OpenCode's schema validation. Route the opencode target through the
  # dedicated converter (agents transformed; skills + commands plain-copied).
  # install-opencode.sh accepts --force and applies it; --copy is a no-op there
  # (opencode install is always a real copy, never a symlink).
  opencode_args=()
  [ "$FORCE" -eq 1 ] && opencode_args+=(--force)
  [ -n "$MODEL_MAP" ] && opencode_args+=(--model-map "$MODEL_MAP")
  bash "$CORE/scripts/install-opencode.sh" "${opencode_args[@]}" || rc=1
else
  refuse_escaped_dest || exit 1
  [ -d "$DEST" ] || {
    echo "install.sh: refusing non-directory destination $DEST" >&2
    exit 1
  }
  if [ "$ADAPTER_MODEL_STRATEGY" = "mapped" ]; then
    subdirs=(agents skills commands scripts)
  else
    subdirs=(agents skills commands scripts)
  fi
  preflight_filesystem_destinations "${subdirs[@]}" || exit 1
  prepare_legacy_knowledge_manager
  if [ "$ADAPTER_MODEL_STRATEGY" = "mapped" ]; then
    materialize_mapped_agents || exit 1
    subdirs=(skills commands scripts)
  fi
  for sub in "${subdirs[@]}"; do
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
    # Re-verify once per subtree: sed -i rewrites files in place inside each of
    # agents/, skills/ and commands/, so a subtree swapped for a symlink since the
    # directory gate would have its linked-to files rewritten.
    for sub in agents skills commands; do
      [ -d "$DEST/$sub" ] || continue
      refuse_escaped_dest || exit 1
      sefi_assert_write_target "$DEST/$sub" "$DEST" \
        "install.sh: refusing to resolve placeholders in $DEST/$sub" || exit 1
      find "$DEST/$sub" -type f -name '*.md' -exec sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$ESCAPED_DEST#g" {} \;
    done
    echo "resolved \${CLAUDE_PLUGIN_ROOT} -> $DEST in agents/skills/commands"
  fi
  # Hook wiring is independent of MODE (it edits settings.json, not the copied/symlinked
  # agent files) and independent of rc for the same reason as the substitution pass above:
  # a skills/ conflict has nothing to do with whether hooks should be wired.
  [ "$TARGET" = "claude-code" ] && wire_claude_settings
fi

if [ "$rc" -ne 0 ]; then
  echo "install.sh: completed with errors (see above)" >&2
  exit 1
fi
if [ "$MODE" = "copy" ]; then
  # Agent frontmatter is generated and prose files have their plugin-root placeholders
  # resolved after copy, so their canonical bytes cannot be checked against the package
  # source. scripts/ is a byte-for-byte copied subtree and can carry a useful manifest.
  write_package_manifest "$CORE/scripts" "$DEST/scripts"
fi
echo "install.sh: done. Target=$TARGET dest=$DEST mode=$MODE"
print_onboarding
