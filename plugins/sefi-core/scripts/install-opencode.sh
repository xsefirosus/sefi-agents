#!/usr/bin/env bash
# install-opencode.sh -- install sefi-core into OpenCode's config directory.
#
# OpenCode auto-discovers agents, skills, and commands under
# ~/.config/opencode/{agents,skills,commands}/. A plain copy is enough for skills
# and commands (their frontmatter has no field collisions with OpenCode's schema).
# Agents are different: OpenCode's `tools` field is a strictly-typed object, not a
# string, and is deprecated in favor of `permission`. A raw agent file fails
# schema validation. The per-file awk transform below converts our comma-separated
# `tools:` and `disallowedTools:` lines into the `permission:` mapping that
# OpenCode expects, leaving every other field and the body byte-for-byte intact.
#
# Usage: bash plugins/sefi-core/scripts/install-opencode.sh [--force]
set -euo pipefail

FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) echo "usage: $0 [--force]"; exit 0 ;;
    *) echo "install-opencode.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

# Resolve source root (this script lives in plugins/sefi-core/scripts/).
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
AGENTS_SRC="$CORE/agents"
SKILLS_SRC="$CORE/skills"
COMMANDS_SRC="$CORE/commands"

# Fail fast if a required source dir is missing.
for d in "$AGENTS_SRC" "$SKILLS_SRC" "$COMMANDS_SRC"; do
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
  for src_dir in "$SKILLS_SRC" "$COMMANDS_SRC"; do
    for entry in "$src_dir"/*; do
      [ -e "$entry" ] || continue
      if [ "$src_dir" = "$SKILLS_SRC" ]; then
        preflight_target "$DEST/skills/$(basename "$entry")"
      else
        preflight_target "$DEST/commands/$(basename "$entry")"
      fi
    done
  done
  if [ "$conflicts" -ne 0 ]; then
    echo "install-opencode.sh: refusing install because $conflicts destination(s) already exist" >&2
    exit 1
  fi
fi

mkdir -p "$DEST/agents" "$DEST/skills" "$DEST/commands"

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
transform_agent() {
  # transform_agent <src-path> <dst-path>
  local src="$1"
  local dst="$2"
  awk '
    BEGIN { in_fm = -1 }

    # First ---: start of frontmatter.
    in_fm == -1 && /^---$/ { in_fm = 0; print; next }

    # Second ---: end of frontmatter. Emit the permission block right before it.
    in_fm == 0 && /^---$/ { emit_permission_block(); print; in_fm = 1; next }

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
      # Every other frontmatter line (description, model, keywords, managed-by,
      # comments, blank lines) is kept verbatim.
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
      if (allow) { print "  " key ": allow"; return }
      deny_hit = 0
      for (j = 1; j <= n; j++) if (parts[j] != "" && parts[j] in deny)  { deny_hit = 1; break }
      if (deny_hit) { print "  " key ": deny"; return }
      print "  " key ": " default_for(key)
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
        if (fm_name == "engineering-manager") return "allow"
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
  echo "transformed agent: $base -> $dst" >&2
  agent_count=$((agent_count + 1))
done

# 2. Skills and 3. Commands -- verbatim copy (no transformation; their
# frontmatter has no field collisions with OpenCode's schema).
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

echo "install-opencode.sh: $agent_count agents transformed; dest=$DEST" >&2
