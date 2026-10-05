#!/usr/bin/env bash
# install-opencode.sh -- install sefi-core into OpenCode's config directory.
#
# OpenCode auto-discovers agents, skills, and commands under
# ~/.config/opencode/{agents,skills,commands}/. A plain copy is enough for skills
# and commands (their frontmatter has no field collisions with OpenCode's schema).
#
# scripts/ is copied too (~/.config/opencode/scripts/), and every copied agent/skill/
# command file has `${CLAUDE_PLUGIN_ROOT}` -- the placeholder agent/skill prose uses to
# reference a bundled script -- rewritten to a literal absolute `$DEST` path at install
# time. OpenCode has no plugin loader to substitute that placeholder at runtime the way
# Claude Code's native /plugin install does, so this installer does it once, here,
# instead: the copied output needs no runtime understanding of the placeholder at all.
# Agents are different: OpenCode's `tools` field is a strictly-typed object, not a
# string, and is deprecated in favor of `permission`. A raw agent file fails
# schema validation. The per-file awk transform below converts our comma-separated
# `tools:` and `disallowedTools:` lines into the `permission:` mapping that
# OpenCode expects, leaving every other field and the body byte-for-byte intact --
# EXCEPT `model:`, which is REPLACED via config/model-map.yml, and `tier:`, which is
# consumed to pick it.
#
# Live-observed on a real OpenCode install (2026-07-19): a bare, harness-specific
# provider alias made OpenCode's own subagent dispatch fail hard. OpenCode does not
# silently ignore an unresolvable per-agent model override; it tries to resolve it as a
# real provider/model identifier and fails when it cannot. Every one of this repo's
# 17 agents then fails, not just the first dispatched specialist.
#
# v0.2.2 fixed that by DROPPING the field. That stopped the crash, but made every
# agent inherit one session model -- so the qa-engineer judged the
# software-engineer on the identical model, and generator/evaluator separation (the
# first design principle in this repo) silently degraded to instructions-only.
# v0.2.4 maps the tier to a real OpenCode model instead: the crash stays fixed and
# the separation comes back the moment the map names two different models.
#
# v0.3.18: config/model-map.yml can map a tier to the literal sentinel "flexible" instead
# of a real model id -- OpenCode Zen's free catalog rotates (deepseek-v4-flash-free, the
# model v0.2.4 pinned, was retired from Zen entirely ten days after being verified real),
# so hardcoding whatever is free this week just breaks again on the next rotation. When a
# tier resolves to "flexible" this script writes NO `model:` line at all for that agent,
# same effect as the v0.2.2 drop -- deliberately, this time, and only for that harness/
# tier, not as a global fallback for every unresolvable value. The human picks a real model
# in OpenCode itself (section 1 of adapters/OPENCODE.md) and every agent inherits it.
#
# `options.reasoningEffort` is written per agent because some OpenCode versions
# exclude DeepSeek models from the reasoning-effort system entirely. It is likewise not
# written when the resolved reasoning is "none" or the model itself is "flexible" -- a
# hardcoded effort value tuned for one specific model's dial is meaningless on a model the
# human chose that this file has no knowledge of.
#
# Live-observed (2026-08-18): with no `mode:` field, OpenCode defaults every agent to
# `mode: all` -- primary (Tab-cycle switchable, a direct human entry point) AND subagent
# (dispatchable) at once. That put all 15 specialists in the same Tab-cycle list as
# engineering-manager, with nothing distinguishing "the one you talk to" from "the ones
# it dispatches" -- the exact direct-invocation path that caused the prompt-engineer
# scope-creep bug this repo's whole check-reply.sh/scope-boundary.md mechanism exists for.
# `mode:` is OpenCode's own native field for this distinction, so this writes it rather
# than inventing a workaround: sefi-agents gets `mode: primary` (the one entry
# point), every other agent gets `mode: subagent` (dispatchable, invisible to Tab-cycle).
#
# Usage: bash plugins/sefi-core/scripts/install-opencode.sh [--force] [--model-map <path>] [--auto-update]
set -euo pipefail

FORCE=0
AUTO_UPDATE=0
MODEL_MAP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --auto-update) AUTO_UPDATE=1; shift ;;
    --model-map) MODEL_MAP="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: $0 [--force] [--model-map <path>] [--auto-update]"; exit 0 ;;
    *) echo "install-opencode.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

# Resolve source root (this script lives in plugins/sefi-core/scripts/).
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
AGENTS_SRC="$CORE/agents"
SKILLS_SRC="$CORE/skills"
COMMANDS_SRC="$CORE/commands"
SCRIPTS_SRC="$CORE/scripts"

agent_model() {
  # agent_model <src-path> -- resolve this agent's tier to an OpenCode model id. A map
  # resolution error is a requested-policy failure, never a silent session-model fallback.
  local map_args=()
  [ -n "$MODEL_MAP" ] && map_args+=(--map "$MODEL_MAP")
  bash "$HERE/model-for.sh" --agent "$1" opencode "${map_args[@]}"
}

agent_reasoning() {
  # agent_reasoning <src-path> -- resolve the corresponding OpenCode reasoning effort.
  # A caller map may intentionally omit effort keys because OpenCode accepts no effort
  # field; that is equivalent to "none", unlike a missing model tier which is fatal.
  local map_args=()
  [ -n "$MODEL_MAP" ] && map_args+=(--map "$MODEL_MAP")
  bash "$HERE/model-for.sh" --agent "$1" opencode --reasoning "${map_args[@]}" 2>/dev/null || printf 'none\n'
}

# Fail fast if a required source dir is missing.
for d in "$AGENTS_SRC" "$SKILLS_SRC" "$COMMANDS_SRC" "$SCRIPTS_SRC"; do
  [ -d "$d" ] || { echo "install-opencode.sh: missing required source dir $d" >&2; exit 1; }
done
[ -z "$MODEL_MAP" ] || [ -f "$MODEL_MAP" ] || { echo "install-opencode.sh: model map not found at $MODEL_MAP" >&2; exit 2; }

# Resolve every agent before creating a destination. A malformed caller map must never
# degrade into an apparently successful install that silently inherits one session model.
for src in "$AGENTS_SRC"/*.md; do
  [ -f "$src" ] || continue
  agent_model "$src" >/dev/null || { echo "install-opencode.sh: cannot resolve model for $(basename "$src")" >&2; exit 1; }
  agent_reasoning "$src" >/dev/null || { echo "install-opencode.sh: cannot resolve reasoning for $(basename "$src")" >&2; exit 1; }
done

# Pick the destination base (mirrors install.sh's opencode target).
DEST="${OPENCODE_HOME:-$HOME/.config/opencode}"
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
  # normalized. Read as a path it is ONE legal relative component -- "C:\Users\you"
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

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sefi-archive.sh"

sefi_assert_write_target() {
  # sefi_assert_write_target <target> <root> <label> -- re-verify at the write site
  # itself that <target> still resolves inside <root>.
  #
  # The directory gate below runs once, before any write. Anyone with write access to
  # a parent directory can swap an already-verified directory for a symlink in the
  # window between that gate and the write, and every later write then lands wherever
  # the symlink points -- a directory gate alone is a check-then-act race. Re-resolving
  # the exact path being written, immediately before the write, closes the window for
  # the whole install: a subtree swapped mid-run is caught by the next write site
  # instead of being followed. Callers pass the path they are about to write (not just
  # DEST), because agents/, skills/, commands/ and scripts/ are the things swapped.
  #
  # sefi: this constrains SYMLINKED DESTINATIONS only. It does not and cannot
  # constrain an arbitrary spelling a caller passed in -- a caller who names a
  # legitimate in-tree path, or one reachable only through a symlink it controls
  # above <root>, has already satisfied the gate, and this is not a sanitiser for
  # caller-supplied path text. Ceiling: a re-check still leaves a sub-millisecond
  # window between this test and the following write, because POSIX shell offers no
  # way to open a directory handle once and write relative to it. Upgrade path: route
  # the staged writes through a small os.open(..., O_NOFOLLOW) helper so the
  # containment decision and the write share one file descriptor.
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
    echo "install-opencode.sh: refusing destination that is not a POSIX path: $DEST" >&2
    return 1
  }
  DEST="$normalized_dest"
  DEST_PHYS="$(sefi_canonical_path "$DEST")" || {
    echo "install-opencode.sh: refusing destination with no physical location: $DEST" >&2
    return 1
  }
  HOME_PHYS="$(sefi_canonical_path "$HOME")" || HOME_PHYS=""
  if [ "$DEST_PHYS" != "$DEST" ] && ! sefi_inside_or_equal "$DEST_PHYS" "$HOME_PHYS"; then
    echo "install-opencode.sh: refusing destination escaping its expected root: $DEST resolves to $DEST_PHYS" >&2
    return 1
  fi
}

refuse_escaped_dest || exit 1
mkdir -p "$DEST"
[ -d "$DEST" ] || {
  echo "install-opencode.sh: refusing non-directory destination $DEST" >&2
  exit 1
}
refuse_escaped_dest || exit 1

PACKAGE_MANIFEST="$HERE/package-manifest.sh"
LEGACY_KNOWLEDGE_MANAGER="$DEST/agents/knowledge-manager.md"
PRESERVE_USER_KNOWLEDGE_MANAGER=0

is_sefi_managed_file() {
  # A same-named legacy profile is removable only when its own source declares Sefi
  # ownership. This never treats a user's file as installer-managed.
  [ -f "$1" ] && grep -q '^[[:space:]]*managed-by:[[:space:]]*sefi-agents[[:space:]]*$' "$1"
}

prepare_legacy_knowledge_manager() {
  [ -e "$LEGACY_KNOWLEDGE_MANAGER" ] || [ -L "$LEGACY_KNOWLEDGE_MANAGER" ] || return 0
  if is_sefi_managed_file "$LEGACY_KNOWLEDGE_MANAGER"; then
    if [ ! -f "$AGENTS_SRC/knowledge-manager.md" ]; then
      rm -f -- "$LEGACY_KNOWLEDGE_MANAGER"
      echo "install-opencode.sh: removed managed legacy knowledge-manager profile" >&2
    fi
    return 0
  fi
  PRESERVE_USER_KNOWLEDGE_MANAGER=1
  echo "install-opencode.sh: preserving user-owned legacy knowledge-manager profile" >&2
}

write_scripts_manifest() {
  # scripts/ is copied byte-for-byte. Agents are transformed and prose has its plugin-root
  # placeholder resolved, so only this subtree has a stable source digest to check.
  local manifest="$DEST/scripts/.sefi-agents-manifest.json"
  [ -f "$PACKAGE_MANIFEST" ] || {
    echo "install-opencode.sh: package manifest helper missing; copied scripts have no manifest" >&2
    return 0
  }
  if [ -e "$manifest" ] && ! grep -q '"format"[[:space:]]*:[[:space:]]*"sefi-package-manifest/v1"' "$manifest" 2>/dev/null; then
    echo "install-opencode.sh: preserving existing user-owned package manifest at $manifest" >&2
    return 0
  fi
  # Re-verify at the write site: the helper below writes into $DEST/scripts, so a
  # scripts/ subtree swapped for a symlink since the directory gate would otherwise be
  # followed straight into it.
  refuse_escaped_dest || return 1
  sefi_assert_write_target "$DEST/scripts" "$DEST" \
    "install-opencode.sh: refusing to write a manifest into $DEST/scripts" || return 1
  bash "$PACKAGE_MANIFEST" create --root "$DEST" --source "$SCRIPTS_SRC" --destination "$DEST/scripts"
  echo "install-opencode.sh: wrote package manifest at $manifest" >&2
}

print_onboarding() {
  cat <<'EOF'
sefi-agents: installation succeeded.
sefi-agents: run /sefi:init once from each project root before the first routed request.
sefi-agents: auto-init is unsafe because installation is user-wide and cannot safely choose or modify a project.
sefi-agents: cross-project memory is optional, local/private, and off by default; /sefi:init asks interactively and keeps it off when unattended.
EOF
}

prepare_legacy_knowledge_manager

run_auto_update_gate() {
  # --auto-update: diff the installed scripts/ manifest against this checkout
  # before writing anything. current exits 0 doing nothing; stale forces the
  # normal install below (the diff just proved scripts/ holds no user edits,
  # so overwriting that subtree is safe); drift without an explicit --force
  # stops with an error and asks, never silently overwriting user edits.
  # sefi: ceiling -- version tracking covers the scripts/ subtree only. A
  # stale update overwrites agents/skills/commands exactly like --force would;
  # those subtrees have no hash baseline to diff against.
  [ "$AUTO_UPDATE" -eq 1 ] || return 0
  local manifest="$DEST/scripts/.sefi-agents-manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "install-opencode.sh: --auto-update found no installed manifest; performing a fresh install" >&2
    return 0
  fi
  local verdict="" rc=0
  verdict="$(bash "$PACKAGE_MANIFEST" diff --root "$DEST" --source "$SCRIPTS_SRC" --destination "$DEST/scripts" 2>&1)" || rc=$?
  case "$verdict" in
    *"package-manifest-diff: current"*)
      echo "install-opencode.sh: --auto-update installed scripts are current; nothing to do" >&2
      exit 0
      ;;
    *"package-manifest-diff: stale"*)
      echo "install-opencode.sh: --auto-update $verdict; updating" >&2
      FORCE=1
      ;;
    *"package-manifest-diff: drift"*)
      if [ "$FORCE" -eq 1 ]; then
        echo "install-opencode.sh: --auto-update $verdict but --force was passed; overwriting" >&2
      else
        echo "install-opencode.sh: --auto-update $verdict; refusing to overwrite user edits (re-run with --force to overwrite, or reconcile by hand)" >&2
        exit 1
      fi
      ;;
    *)
      echo "install-opencode.sh: --auto-update could not determine installed state (exit $rc): $verdict" >&2
      exit 1
      ;;
  esac
}
run_auto_update_gate

# Refuse a no-force install before writing anything. Checking every target up front
# avoids a partial install when only some agent, skill, or command names conflict.
conflicts=0
preflight_target() {
  # preflight_target <dest-path>
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "install-opencode.sh: refusing to overwrite $target (use --force)" >&2
    conflicts=$((conflicts + 1))
  fi
}

if [ "$FORCE" -ne 1 ]; then
  for src in "$AGENTS_SRC"/*.md; do
    [ -f "$src" ] || continue
    preflight_target "$DEST/agents/$(basename "$src")"
  done
  for src_dir in "$SKILLS_SRC" "$COMMANDS_SRC" "$SCRIPTS_SRC"; do
    for entry in "$src_dir"/*; do
      [ -e "$entry" ] || continue
      case "$src_dir" in
        "$SKILLS_SRC")   preflight_target "$DEST/skills/$(basename "$entry")" ;;
        "$COMMANDS_SRC") preflight_target "$DEST/commands/$(basename "$entry")" ;;
        *)               preflight_target "$DEST/scripts/$(basename "$entry")" ;;
      esac
    done
  done
  if [ "$conflicts" -ne 0 ]; then
    echo "install-opencode.sh: refusing install because $conflicts destination(s) already exist" >&2
    exit 1
  fi
fi

refuse_escaped_dest || exit 1
[ -d "$DEST" ] || {
  echo "install-opencode.sh: refusing non-directory destination $DEST" >&2
  exit 1
}
# Resolve each subtree before the mkdir that creates it. refuse_escaped_dest above settles
# DEST itself, but a subtree that is already a symlink pointing outside DEST passes that
# check and would be created through by the mkdir below -- the one write site here with no
# per-file check after it. Refusing first keeps the containment decision ahead of the write.
for sefi_sub in agents skills commands scripts; do
  sefi_assert_write_target "$DEST/$sefi_sub" "$DEST" \
    "install-opencode.sh: refusing to create $DEST/$sefi_sub" || exit 1
done
mkdir -p "$DEST/agents" "$DEST/skills" "$DEST/commands" "$DEST/scripts"
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

# Per-file check: refuse to overwrite unless --force was passed.
check_target() {
  # check_target <dest-path>
  local target="$1"
  # Re-verify containment at every write site, not once at the directory gate: a
  # caller with write access to DEST can swap a subtree for a symlink after the gate
  # passes, and this is the function that is about to delete and replace it.
  refuse_escaped_dest || return 1
  sefi_assert_write_target "$target" "$DEST" \
    "install-opencode.sh: refusing to write $target" || return 1
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "install-opencode.sh: refusing to overwrite $target (use --force)" >&2
      return 1
    fi
    # Archive before the delete, not after. --force means "replace what is
    # there", and what is there may be a file the user hand-edited; a hard rm
    # made that unrecoverable. sefi_archive_put copies first and returns
    # non-zero if the copy failed, so a target we cannot archive is one we do
    # not touch -- the delete is the reclaim, the copy is the safety net.
    #
    # The rm below does not follow the link either way: `rm -rf` on a symlink
    # removes the link, never its target. So when the target is a symlink there
    # is nothing to archive -- sefi_archive_put refuses symlinks precisely so it
    # cannot copy through one -- and forcing a failure here would replace the
    # link with a real file, which is the documented --force behavior and what
    # the "never follows the swapped symlink" assertion requires.
    if [ ! -L "$target" ]; then
      sefi_archive_put "$target" --label "opencode-$(basename "$target")" \
        || return 1
    fi
    rm -rf "$target"
  fi
  return 0
}

# 1. Agents -- transform each .md: replace the `tools:` line with a
# `permission:` block in the format OpenCode's schema accepts, leaving every
# other frontmatter field and the body byte-for-byte intact.
#
# Algorithm (per the install plan):
#   - Parse `tools:` into an ALLOW set; parse `disallowedTools:` into a DENY set.
#   - Map each Claude-Code tool name to an OpenCode permission key:
#       Read/Grep/Glob/Bash -> read/grep/glob/bash
#       Write/Edit/MultiEdit -> edit
#       WebFetch/WebSearch -> webfetch/websearch
#   - For each of 15 OpenCode permission keys (in the order the plan specifies),
#     compute the value with this exact precedence:
#       (a) any source tool for this key is in ALLOW -> "allow"
#       (b) any source tool for this key is in DENY -> "deny"
#       (c) else: use the fixed fallback table, with engineering-manager
#           specifically getting task: allow (it is this repo's sole dispatcher
#           agent -- every other agent's own Role text says it does not delegate).
transform_agent() {
  # transform_agent <src-path> <dst-path>
  local src="$1"
  local dst="$2"
  local model reasoning
  model="$(agent_model "$src")" || return 1
  reasoning="$(agent_reasoning "$src")" || return 1
  awk -v MODEL="$model" -v REASONING="$reasoning" '
    BEGIN { in_fm = -1 }

    # First ---: start of frontmatter.
    in_fm == -1 && /^---$/ { in_fm = 0; print; next }

    # Second ---: end of frontmatter. Emit mapped model, mode, and permission block right before it.
    in_fm == 0 && /^---$/ {
      emit_model_fields()
      if (fm_name == "sefi-agents" || fm_name == "engineering-manager") { print "mode: primary" }
      else { print "mode: subagent" }
      emit_permission_block(); print; in_fm = 1; next
    }

    # Inside frontmatter: capture name, tools, disallowedTools; print others as-is.
    in_fm == 0 {
      if (/^name:[[:space:]]*/) {
        line = $0; sub(/^name:[[:space:]]*/, "", line); fm_name = line
        print; next
      }
      if (/^tools:[[:space:]]*/) {
        line = $0; sub(/^tools:[[:space:]]*/, "", line)
        n = split(line, parts, ",")
        for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", parts[i]); if (parts[i] != "") tools[parts[i]] = 1 }
        next   # replaced by the permission block; do not print this line
      }
      if (/^disallowedTools:[[:space:]]*/) {
        line = $0; sub(/^disallowedTools:[[:space:]]*/, "", line)
        n = split(line, parts, ",")
        for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", parts[i]); if (parts[i] != "") deny[parts[i]] = 1 }
        print; next
      }
      if (/^tier:[[:space:]]*/) {
        next   # harness-neutral input, not an OpenCode field; consumed to pick MODEL.
      }
      # Every other frontmatter line (description, keywords, managed-by, comments,
      # blank lines) is kept verbatim.
      print; next
    }

    # Body: print as-is.
    { print }

    function emit_permission_block(   i) {
      print "permission:"
      print_perm_line("read",              "Read")
      print_perm_line("edit",              "Write,Edit,MultiEdit")
      print_perm_line("glob",              "Glob")
      print_perm_line("grep",              "Grep")
      print_perm_line("list",              "")
      print_perm_line("bash",              "Bash")
      print_perm_line("task",              "")
      print_perm_line("external_directory","")
      print_perm_line("todowrite",         "")
      print_perm_line("question",          "")
      print_perm_line("webfetch",          "WebFetch")
      print_perm_line("websearch",         "WebSearch")
      print_perm_line("lsp",               "")
      print_perm_line("doom_loop",         "")
      print_perm_line("skill",             "")
    }

    function emit_model_fields() {
      if (MODEL != "" && MODEL != "flexible") { print "model: " MODEL }
      if (REASONING != "" && REASONING != "none" && MODEL != "flexible") {
        print "options:"
        print "  reasoningEffort: " REASONING
      }
    }

    function print_perm_line(key, sources,   parts, n, j, allow, deny_hit) {
      n = split(sources, parts, ",")
      allow = 0
      for (j = 1; j <= n; j++) if (parts[j] != "" && parts[j] in tools) { allow = 1; break }
      if (allow) {
        # bash is special: an agent that fully disallows Write, Edit, AND MultiEdit --
        # i.e. already claims to never touch file content -- gets a pattern-map deny list
        # instead of a flat allow, because Bash can otherwise write files by other means
        # (sed -i, tee, shell redirection) with nothing to stop it. Live-confirmed
        # 2026-08-18: an engineering-manager session used exactly this route (Bash-invoked
        # Add-Content/sed -i) to violate its own disallowedTools. Same dynamic check as
        # scripts/check-bash-write.sh (the equivalent Claude Code gate), so both stay in
        # sync with no second list to go stale.
        if (key == "bash" && ("Write" in deny) && ("Edit" in deny) && ("MultiEdit" in deny)) {
          emit_bash_write_gate(); return
        }
        print "  " key ": allow"; return
      }
      deny_hit = 0
      for (j = 1; j <= n; j++) if (parts[j] != "" && parts[j] in deny)  { deny_hit = 1; break }
      if (deny_hit) { print "  " key ": deny"; return }
      print "  " key ": " default_for(key)
    }

    function emit_bash_write_gate() {
      # OpenCode bash permission rules match in order; the LAST matching rule wins, so the
      # catch-all "*": allow must come first and every deny pattern after it. Same pattern
      # classes as check-bash-write.sh grep/case checks, expressed as OpenCode globs
      # instead: in-place editors, tee, dd of=, PowerShell content-write cmdlets, cp/mv, and
      # shell redirection. Unverified against a live OpenCode install (this repo has no
      # runtime to test against); the equivalent Claude Code hook was live-tested via
      # test-scripts.sh, this was not.
      print "  bash:"
      print "    \"*\": allow"
      print "    \"sed -i*\": deny"
      print "    \"sed --in-place*\": deny"
      print "    \"perl -i*\": deny"
      print "    \"perl -pi*\": deny"
      print "    \"tee *\": deny"
      print "    \"dd *of=*\": deny"
      print "    \"*Add-Content*\": deny"
      print "    \"*Set-Content*\": deny"
      print "    \"*Out-File*\": deny"
      print "    \"*New-Item*ItemType*File*\": deny"
      print "    \"*[System.IO.File]*\": deny"
      print "    \"cp *\": deny"
      print "    \"mv *\": deny"
      print "    \"* > *\": deny"
      print "    \"* >> *\": deny"
    }

    function default_for(key) {
      if (key == "skill") return "allow"
      if (key == "list") return "allow"
      if (key == "question") return "allow"
      if (key == "lsp") return "allow"
      if (key == "external_directory") return "ask"
      if (key == "doom_loop") return "ask"
      if (key == "todowrite") return "deny"
      if (key == "task") {
        if (fm_name == "sefi-agents" || fm_name == "engineering-manager") return "allow"
        return "deny"
      }
      return "deny"
    }
  ' "$src" > "$dst"
}

# One archive for the whole run. This must sit before the first call that can
# delete anything: the agent loop below calls check_target, which archives and
# then rm -rf's, and sefi_archive_put refuses to run without an archive root.
sefi_archive_init "opencode-install" || exit 1

agent_count=0
for src in "$AGENTS_SRC"/*.md; do
  [ -f "$src" ] || continue
  base="$(basename "$src")"
  dst="$DEST/agents/$base"
  if [ "$base" = "knowledge-manager.md" ] && [ "$PRESERVE_USER_KNOWLEDGE_MANAGER" -eq 1 ]; then
    echo "install-opencode.sh: skipped user-owned legacy knowledge-manager profile" >&2
    continue
  fi
  # FAILURE SEMANTICS (fail-closed): any check_target failure -- a containment
  # refusal, an overwrite refusal, or above all an archive-put copy failure --
  # aborts the whole install with a non-zero exit after attempting an archive
  # restore. It must NEVER degrade to skipping the agent and reporting success:
  # an archive-put failure followed by `continue` would yield an exit-0 install
  # with silently missing agents, which reads as success while destroying the
  # operator's ability to notice what did not land. The knowledge-manager skip
  # above is the only sanctioned `continue`: preserving a user-owned file by
  # request, explicitly logged, not a failure at all.
  if ! check_target "$dst"; then
    echo "install-opencode.sh: cannot protect $dst -- refusing to continue with a missing agent (snapshot failure fails closed, nothing was deleted for this target)" >&2
    sefi_archive_restore || true
    exit 1
  fi
  # Render through a staging file moved into place, so a symlink swapped in
  # after the target check cannot divert the transformed write into another
  # file: the write lands on a file this install owns, and mv replaces (never
  # follows) whatever sits at the destination.
  #
  # NEW-2: re-verify containment at the write site. The staging mktemp below
  # creates a file inside $DEST/agents, and check_target's rm -rf is the window
  # an attacker with write access to DEST would use to swap that subtree.
  refuse_escaped_dest || exit 1
  sefi_assert_write_target "$dst" "$DEST" \
    "install-opencode.sh: refusing to write $dst" || exit 1
  sefi_assert_write_target "$DEST/agents" "$DEST" \
    "install-opencode.sh: refusing to stage agent content in $DEST/agents" || exit 1
  # NEW-7: both statuses are checked before the mv. An unchecked mktemp hands the
  # next command an empty destination string, and an unchecked transform_agent makes
  # a failed awk a silent success that installs a truncated agent profile.
  agent_tmp="$(mktemp "$DEST/agents/.sefi-agent.XXXXXX")" || {
    echo "install-opencode.sh: cannot create a staging file in $DEST/agents" >&2
    exit 1
  }
  # Re-verify immediately after staging too: mktemp is the first filesystem call at
  # this write site, so a subtree swapped during it must be caught before the
  # transformed profile bytes are rendered into the staging file.
  if ! sefi_assert_write_target "$agent_tmp" "$DEST" \
    "install-opencode.sh: refusing to stage $dst" || ! sefi_assert_write_target "$DEST/agents" "$DEST" \
    "install-opencode.sh: refusing to stage agent content in $DEST/agents"; then
    rm -f "$agent_tmp"
    exit 1
  fi
  if ! transform_agent "$src" "$agent_tmp"; then
    rm -f "$agent_tmp"
    echo "install-opencode.sh: cannot transform $base into $dst" >&2
    exit 1
  fi
  # OpenCode has no plugin loader to substitute ${CLAUDE_PLUGIN_ROOT} at runtime the way
  # Claude Code's native /plugin install does, so it is resolved here at install time
  # instead, to a literal absolute path -- a copied install needs no runtime understanding
  # of the placeholder at all.
  sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$ESCAPED_DEST#g" "$agent_tmp"
  # Re-verify after the transform, immediately before the move into place.
  refuse_escaped_dest || { rm -f "$agent_tmp"; exit 1; }
  sefi_assert_write_target "$dst" "$DEST" \
    "install-opencode.sh: refusing to write $dst" || { rm -f "$agent_tmp"; exit 1; }
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    rm -f "$agent_tmp"
    echo "install-opencode.sh: refusing install target that reappeared: $dst" >&2
    exit 1
  fi
  mv "$agent_tmp" "$dst"
  echo "transformed agent: $base -> $dst" >&2
  agent_count=$((agent_count + 1))
done

# 2. Skills, 3. Commands, and 4. Scripts -- verbatim copy (no transformation; skill and
# command frontmatter has no field collisions with OpenCode's schema, and scripts are
# plain shell).
copy_dir() {
  # copy_dir <src-dir> <dest-dir> <label>
  local src_dir="$1"
  local dst_dir="$2"
  local label="$3"
  local count=0
  for entry in "$src_dir"/*; do
    [ -e "$entry" ] || continue
    local base="$(basename "$entry")"
    local target="$dst_dir/$base"
    # Same failure semantics as the agent loop above: a check_target failure
    # (including an archive-put failure) returns 1 so the caller restores the
    # archive and exits non-zero -- never a silent skip that reports success
    # with silently missing files.
    if ! check_target "$target"; then
      echo "install-opencode.sh: cannot protect $target -- refusing to continue with a missing $label (snapshot failure fails closed, nothing was deleted for this target)" >&2
      return 1
    fi
    # Re-verify after check_target's rm -rf and immediately before the copy: that
    # removal is the window a directory swap would target.
    refuse_escaped_dest || return 1
    sefi_assert_write_target "$target" "$DEST" \
      "install-opencode.sh: refusing to write $target" || return 1
    cp -R "$entry" "$target" || return 1
    echo "copied $label: $base -> $target" >&2
    count=$((count + 1))
  done
  return 0
}

copy_dir "$SKILLS_SRC" "$DEST/skills" "skill" || { sefi_archive_restore; exit 1; }
copy_dir "$COMMANDS_SRC" "$DEST/commands" "command" || { sefi_archive_restore; exit 1; }
copy_dir "$SCRIPTS_SRC" "$DEST/scripts" "script" || { sefi_archive_restore; exit 1; }

# Same placeholder resolution as the agent transform above, applied to copied skills and
# commands (scripts/ itself never contains the placeholder -- it is what it resolves to).
# Re-verify each subtree immediately before rewriting its files in place.
for sub in skills commands; do
  [ -d "$DEST/$sub" ] || continue
  refuse_escaped_dest || exit 1
  sefi_assert_write_target "$DEST/$sub" "$DEST" \
    "install-opencode.sh: refusing to resolve placeholders in $DEST/$sub" || exit 1
  find "$DEST/$sub" -type f -name '*.md' -exec sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$ESCAPED_DEST#g" {} \;
done

write_scripts_manifest
echo "install-opencode.sh: $agent_count agents transformed; dest=$DEST" >&2
# Everything landed, so the archive has no further job. Purge failure is not
# fatal: the install itself succeeded, and leaving a temp archive behind is a
# far smaller problem than reporting a failed install that actually worked.
sefi_archive_purge >/dev/null 2>&1 || true
print_onboarding
