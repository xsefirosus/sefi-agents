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
# Live-observed on a real OpenCode install (2026-07-19): `model: sonnet` (a bare
# Claude Code tier alias) makes OpenCode's own subagent dispatch fail hard with
# "Model not found: sonnet/" -- OpenCode does not silently ignore an unresolvable
# per-agent model override the way Claude Code treats "sonnet" as a native alias;
# it tries to resolve it as a real provider/model identifier and fails when it
# can't. Every one of this repo's 13 agents carries a `model:` line, so this broke
# every subagent dispatch on OpenCode, not just one agent.
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
# (dispatchable) at once. That put all 13 specialists in the same Tab-cycle list as
# engineering-manager, with nothing distinguishing "the one you talk to" from "the ones
# it dispatches" -- the exact direct-invocation path that caused the prompt-engineer
# scope-creep bug this repo's whole check-reply.sh/scope-boundary.md mechanism exists for.
# `mode:` is OpenCode's own native field for this distinction, so this writes it rather
# than inventing a workaround: engineering-manager gets `mode: primary` (the one entry
# point), every other agent gets `mode: subagent` (dispatchable, invisible to Tab-cycle).
#
# Usage: bash plugins/sefi-core/scripts/install-opencode.sh [--force] [--model-map <path>]
set -euo pipefail

FORCE=0
MODEL_MAP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --model-map) MODEL_MAP="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: $0 [--force] [--model-map <path>]"; exit 0 ;;
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

# Fail fast if a required source dir is missing.
for d in "$AGENTS_SRC" "$SKILLS_SRC" "$COMMANDS_SRC" "$SCRIPTS_SRC"; do
  [ -d "$d" ] || { echo "install-opencode.sh: missing required source dir $d" >&2; exit 1; }
done

# Pick the destination base (mirrors install.sh's opencode target).
DEST="${OPENCODE_HOME:-$HOME/.config/opencode}"
# On Cygwin/MSYS, normalize a Windows-style HOME to a POSIX path.
if command -v cygpath >/dev/null 2>&1; then
  DEST="$(cygpath -u "$DEST")"
fi

mkdir -p "$DEST"

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

mkdir -p "$DEST/agents" "$DEST/skills" "$DEST/commands" "$DEST/scripts"

# Per-file check: refuse to overwrite unless --force was passed.
check_target() {
  # check_target <dest-path>
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "install-opencode.sh: refusing to overwrite $target (use --force)" >&2
      return 1
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
agent_model() {
  # agent_model <src-path> -- resolve this agent's tier to an OpenCode model id via
  # config/model-map.yml. Empty on failure, which drops the field and restores the old
  # fall-back-to-session-model behavior rather than emitting a broken value.
  bash "$HERE/model-for.sh" --agent "$1" opencode ${MODEL_MAP:+--map "$MODEL_MAP"} 2>/dev/null || printf ''
}

agent_reasoning() {
  # agent_reasoning <src-path> -- resolve this agent's tier to an OpenCode reasoning effort.
  bash "$HERE/model-for.sh" --agent "$1" opencode --reasoning ${MODEL_MAP:+--map "$MODEL_MAP"} 2>/dev/null || printf ''
}

transform_agent() {
  # transform_agent <src-path> <dst-path>
  local src="$1"
  local dst="$2"
  awk -v MODEL="$(agent_model "$src")" -v REASONING="$(agent_reasoning "$src")" '
    BEGIN { in_fm = -1 }

    # First ---: start of frontmatter.
    in_fm == -1 && /^---$/ { in_fm = 0; print; next }

    # Second ---: end of frontmatter. Emit mode: and the permission block right before it.
    in_fm == 0 && /^---$/ {
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
      if (/^model:[[:space:]]*/) {
        # The Claude Code alias is replaced, not dropped. Dropping it (the v0.2.2 fix)
        # stopped the crash but made every agent inherit ONE session model, which
        # collapses generator/evaluator separation: the qa-engineer and the
        # software-engineer it judges ran on the identical model, so the routing
        # table rule "different model where possible" was never possible here.
        #
        # EXCEPT when the map itself says "flexible" (v0.3.18): that is a deliberate
        # per-tier choice, not a missing/unresolvable value, so the drop below is by
        # design -- the users own OpenCode model selection governs instead.
        if (MODEL != "" && MODEL != "flexible") { print "model: " MODEL }
        # Some OpenCode versions exclude DeepSeek models from the reasoning-effort system
        # and need options.reasoningEffort set per agent, so it is written here rather than
        # assumed. Effort scales with tier: the high tier is the adversarial judge and the
        # long agent loop, which is where more reasoning actually pays for itself. Not
        # written for "flexible" either: an effort value tuned for one models own dial is
        # meaningless (or rejected) on a model this file has no knowledge of.
        if (REASONING != "" && REASONING != "none" && MODEL != "flexible") {
          print "options:"
          print "  reasoningEffort: " REASONING
        }
        next
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

agent_count=0
for src in "$AGENTS_SRC"/*.md; do
  [ -f "$src" ] || continue
  base="$(basename "$src")"
  dst="$DEST/agents/$base"
  if ! check_target "$dst"; then continue; fi
  transform_agent "$src" "$dst"
  # OpenCode has no plugin loader to substitute ${CLAUDE_PLUGIN_ROOT} at runtime the way
  # Claude Code's native /plugin install does, so it is resolved here at install time
  # instead, to a literal absolute path -- a copied install needs no runtime understanding
  # of the placeholder at all.
  sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g" "$dst"
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
    if ! check_target "$target"; then continue; fi
    cp -R "$entry" "$target"
    echo "copied $label: $base -> $target" >&2
    count=$((count + 1))
  done
  return 0
}

copy_dir "$SKILLS_SRC" "$DEST/skills" "skill"
copy_dir "$COMMANDS_SRC" "$DEST/commands" "command"
copy_dir "$SCRIPTS_SRC" "$DEST/scripts" "script"

# Same placeholder resolution as the agent transform above, applied to copied skills and
# commands (scripts/ itself never contains the placeholder -- it is what it resolves to).
find "$DEST/skills" "$DEST/commands" -type f -name '*.md' -exec sed -i "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g" {} \;

echo "install-opencode.sh: $agent_count agents transformed; dest=$DEST" >&2
