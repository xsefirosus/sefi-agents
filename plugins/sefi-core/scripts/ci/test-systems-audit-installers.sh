#!/usr/bin/env bash
# Offline installer acceptance checks for the systems-audit runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
HERMES_INSTALL="$CORE/scripts/install-hermes.sh"
OPENCODE_INSTALL="$CORE/scripts/install-opencode.sh"
BASE_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
BASE_TREE="$(git -C "$ROOT" rev-parse HEAD^{tree})"
CANDIDATE_TREE="$(git -C "$ROOT" write-tree)"
CANDIDATE_PATCH_SHA256="$(git -C "$ROOT" diff --cached --binary | sha256sum | awk '{print $1}')"
EMPTY_PATCH_SHA256="$(printf '' | sha256sum | awk '{print $1}')"
if [ "$CANDIDATE_TREE" = "$BASE_TREE" ]; then
  CANDIDATE_IDENTITY="clean-committed"
else
  CANDIDATE_IDENTITY="staged"
fi
tmp="$(mktemp -d)"
tmp_resolved="$(cd -P "$tmp" && pwd -P)"

path_inside() {
  # path_inside <candidate> <root> -- succeed when <candidate> is <root> or below it.
  # A literal prefix test, never a glob, so a root containing glob characters compares
  # literally instead of expanding.
  local candidate="$1" root="$2"
  [ -n "$candidate" ] && [ -n "$root" ] || return 1
  [ "$candidate" = "$root" ] && return 0
  [ "${candidate:0:${#root}}" = "$root" ] || return 1
  [ "${candidate:${#root}:1}" = "/" ] || return 1
  return 0
}

# The installers accept a destination that resolves anywhere inside HOME, by design (a
# user who symlinks their dotfiles tree is a supported layout, not an escape). That same
# tolerance makes HOME the wrong place to stage a fixture whose expected outcome is a
# refusal: on a host whose TMPDIR sits inside HOME, a symlinked-parent destination staged
# under the ordinary fixture temp is accepted by the gate, the installer proceeds, and the
# case fails for a reason that has nothing to do with the guard under test. These cases
# therefore get their own temp under a system directory, with the same physical-spelling
# check the byte-equality assertions below use: a candidate that cannot be created, or
# whose physical location is not byte-identical to its spelling, or that turns out to be
# inside HOME after all, leaves outside_home_temp empty and those cases PENDING rather
# than claiming a refusal the host could not produce.
outside_home_temp=""
for outside_home_root in /tmp /var/tmp; do
  [ -d "$outside_home_root" ] || continue
  outside_home_candidate="$(mktemp -d "$outside_home_root/sefi-installer-outside-home.XXXXXX" 2>/dev/null)" || continue
  outside_home_phys="$(cd -P "$outside_home_candidate" 2>/dev/null && pwd -P)" || outside_home_phys=""
  home_phys="$(cd -P "$HOME" 2>/dev/null && pwd -P)" || home_phys=""
  if [ -n "$outside_home_phys" ] && [ "$outside_home_phys" = "$outside_home_candidate" ] \
    && [ -n "$home_phys" ] && ! path_inside "$outside_home_phys" "$home_phys"; then
    outside_home_temp="$outside_home_candidate"
    break
  fi
  rm -rf -- "$outside_home_candidate"
done
[ -n "$outside_home_temp" ] || printf 'PENDING: escape-refusal cases need a physical fixture temp outside $HOME (got %s)\n' "${outside_home_candidate:-none}"

safe_remove_under_tmp() {
  # Resolve each recursive-delete target before acting. These fixtures run on Windows too,
  # where an unintended drive-root or profile-root target would be unrecoverable. Both
  # fixture temps are allowed roots, and each was created by this file, so the check is
  # the same containment test for both rather than a wildcard.
  local target="$1" parent resolved allowed
  parent="$(dirname "$target")"
  resolved="$(cd -P "$parent" && pwd -P)/$(basename "$target")"
  for allowed in "$tmp_resolved" ${outside_home_temp:+"$outside_home_temp"}; do
    if path_inside "$resolved" "$allowed"; then
      rm -rf -- "$resolved"
      return 0
    fi
  done
  printf 'REFUSED: cleanup target escapes fixture temp directory: %s\n' "$resolved" >&2
  return 1
}

cleanup() {
  safe_remove_under_tmp "$tmp" || :
  [ -n "$outside_home_temp" ] && { safe_remove_under_tmp "$outside_home_temp" || :; }
  return 0
}
trap cleanup EXIT

fail=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
expect_success() {
  local label="$1"
  shift
  if "$@" >"$tmp/$label.out" 2>&1; then ok "$label"; else cat "$tmp/$label.out" >&2; bad "$label"; fi
}
expect_failure() {
  local label="$1"
  shift
  if "$@" >"$tmp/$label.out" 2>&1; then cat "$tmp/$label.out" >&2; bad "$label"; else ok "$label"; fi
}

if safe_remove_under_tmp "$tmp_resolved/../sefi-installer-cleanup-outside"; then
  bad "fixture cleanup refuses targets outside its temporary directory"
else
  ok "fixture cleanup refuses targets outside its temporary directory"
fi

# Claude Code's isolated candidate package retains both the invocation and the canonical
# auditor source that the native plugin loader discovers from its manifest.
claude_candidate="$tmp/claude-candidate"
mkdir -p "$claude_candidate"
cp -R "$CORE/." "$claude_candidate/"
if [ -f "$claude_candidate/commands/audit.md" ] \
  && [ -f "$claude_candidate/agents/systems-auditor.md" ] \
  && [ -f "$claude_candidate/skills/systems-audit/SKILL.md" ] \
  && grep -Fq '"./skills/"' "$claude_candidate/.claude-plugin/plugin.json"; then
  ok "Claude Code isolated candidate exposes audit invocation and auditor"
else
  bad "Claude Code isolated candidate exposes audit invocation and auditor"
fi
claude_home="$tmp/claude-home"
expect_success "Claude Code fallback install includes systems-audit" \
  env HOME="$claude_home" bash "$ROOT/install.sh" --target claude --copy
if [ -f "$claude_home/.claude/skills/systems-audit/SKILL.md" ] \
  && [ -f "$claude_home/.claude/agents/systems-auditor.md" ] \
  && [ -f "$claude_home/.claude/commands/audit.md" ]; then
  ok "Claude Code fallback retains audit invocation and auditor"
else
  bad "Claude Code fallback retains audit invocation and auditor"
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: install.sh parent-symlink check needs a fixture temp outside $HOME\n'
else
  sh_parent_base="$outside_home_temp/sh-parent-base"
  sh_parent_victim="$outside_home_temp/sh-parent-victim"
  mkdir -p "$sh_parent_base" "$sh_parent_victim"
  printf 'victim content\n' > "$sh_parent_victim/keep.txt"
  if ln -s "$sh_parent_victim" "$sh_parent_base/link" 2>/dev/null \
    && [ -L "$sh_parent_base/link" ]; then
    expect_failure "install.sh refuses a symlinked DEST parent" \
      env HERMES_HOME="$sh_parent_base/link/subdir" bash "$ROOT/install.sh" --target hermes --copy
    if [ ! -e "$sh_parent_victim/subdir" ] \
      && [ ! -e "$sh_parent_victim/agents" ] \
      && grep -qxF 'victim content' "$sh_parent_victim/keep.txt"; then
      ok "install.sh symlinked parent leaves victim unchanged"
    else
      bad "install.sh symlinked parent leaves victim unchanged"
    fi
  else
    printf 'PENDING: install.sh parent-symlink check requires a physical symlink\n'
  fi
fi

if command -v jq >/dev/null 2>&1; then
  settings_home="$tmp/settings-dangling-home"
  settings_dest="$settings_home/.claude"
  mkdir -p "$settings_dest"
  if ln -s "$tmp/settings-dangling-victim" "$settings_dest/settings.json" 2>/dev/null \
    && [ -L "$settings_dest/settings.json" ]; then
    expect_failure "install.sh refuses a dangling settings.json symlink" \
      env HOME="$settings_home" bash "$ROOT/install.sh" --target claude --copy
    if [ ! -e "$tmp/settings-dangling-victim" ] \
      && [ -L "$settings_dest/settings.json" ]; then
      ok "install.sh dangling settings symlink leaves its target uncreated"
    else
      bad "install.sh dangling settings symlink leaves its target uncreated"
    fi
  else
    printf 'PENDING: install.sh settings-symlink check requires a physical symlink\n'
  fi
  settings_live_home="$tmp/settings-live-home"
  settings_live_victim="$tmp/settings-live-victim.md"
  mkdir -p "$settings_live_home/.claude"
  printf 'live victim settings\n' > "$settings_live_victim"
  if ln -s "$settings_live_victim" "$settings_live_home/.claude/settings.json" 2>/dev/null \
    && [ -L "$settings_live_home/.claude/settings.json" ]; then
    expect_failure "install.sh refuses a live settings.json symlink" \
      env HOME="$settings_live_home" bash "$ROOT/install.sh" --target claude --copy
    if grep -qxF 'live victim settings' "$settings_live_victim" \
      && [ -L "$settings_live_home/.claude/settings.json" ]; then
      ok "install.sh live settings symlink leaves its target unmodified"
    else
      bad "install.sh live settings symlink leaves its target unmodified"
    fi
  else
    printf 'PENDING: install.sh live-settings check requires a physical symlink\n'
  fi

  # Behavioral replacement for a grep assertion on '.sefi-settings.'. A grep for the
  # staging prefix can only prove the string is still present: deleting every guarded
  # line and leaving the comment behind passes it. What is actually asserted here is
  # the observable outcome the staging exists to produce -- the merged file exists, is
  # a regular file rather than something reached through a link, carries the merge,
  # and leaves no staging artifact behind. Inside the jq guard, because without jq
  # install.sh deliberately does not wire settings.json at all.
  settings_stage_home="$tmp/settings-staged-home"
  expect_success "install.sh creates and merges settings.json through a staged file" \
    env HOME="$settings_stage_home" bash "$ROOT/install.sh" --target claude --copy
  settings_stage_file="$settings_stage_home/.claude/settings.json"
  if [ -f "$settings_stage_file" ] && [ ! -L "$settings_stage_file" ] \
    && grep -q 'CLAUDE_PLUGIN_ROOT' "$settings_stage_file" \
    && grep -q 'SessionStart' "$settings_stage_file" \
    && [ -z "$(find "$settings_stage_home/.claude" -maxdepth 1 -name '.sefi-settings*' -print -quit 2>/dev/null || true)" ]; then
    ok "install.sh leaves a merged regular settings.json and no staging leftover"
  else
    bad "install.sh leaves a merged regular settings.json and no staging leftover"
  fi
else
  printf 'PENDING: install.sh settings-symlink check requires jq\n'
fi

sh_amp_home="$tmp/sh-amp&test"
expect_success "install.sh resolves placeholders when DEST contains ampersand" \
  env HERMES_HOME="$sh_amp_home" bash "$ROOT/install.sh" --target hermes --copy
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$sh_amp_home/agents" "$sh_amp_home/skills" "$sh_amp_home/commands" >/dev/null 2>&1; then
  bad "install.sh ampersand DEST left an unresolved placeholder"
else
  ok "install.sh ampersand DEST left no unresolved placeholder"
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: install.sh existing-subdir check needs a fixture temp outside $HOME\n'
else
  sh_existing_base="$outside_home_temp/sh-existing-base"
  sh_existing_victim="$outside_home_temp/sh-existing-victim"
  mkdir -p "$sh_existing_base" "$sh_existing_victim/subdir"
printf 'victim content\n' > "$sh_existing_victim/keep.txt"
printf 'victim subdir content\n' > "$sh_existing_victim/subdir/keep.txt"
if ln -s "$sh_existing_victim" "$sh_existing_base/link" 2>/dev/null \
  && [ -L "$sh_existing_base/link" ]; then
  expect_failure "install.sh refuses an existing subdir via a symlinked parent" \
    env HERMES_HOME="$sh_existing_base/link/subdir" bash "$ROOT/install.sh" --target hermes --copy
  if [ ! -e "$sh_existing_victim/subdir/agents" ] \
    && [ ! -e "$sh_existing_victim/subdir/skills" ] \
    && grep -qxF 'victim subdir content' "$sh_existing_victim/subdir/keep.txt" \
    && grep -qxF 'victim content' "$sh_existing_victim/keep.txt"; then
    ok "install.sh existing subdir via symlinked parent leaves victim unchanged"
  else
    bad "install.sh existing subdir via symlinked parent leaves victim unchanged"
  fi
else
  printf 'PENDING: install.sh existing-subdir check requires a physical symlink\n'
  fi
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: install.sh trailing-slash check needs a fixture temp outside $HOME\n'
else
  sh_tslash_base="$outside_home_temp/sh-tslash-base"
  sh_tslash_victim="$outside_home_temp/sh-tslash-victim"
  mkdir -p "$sh_tslash_base" "$sh_tslash_victim"
printf 'victim content\n' > "$sh_tslash_victim/keep.txt"
if ln -s "$sh_tslash_victim" "$sh_tslash_base/link" 2>/dev/null \
  && [ -L "$sh_tslash_base/link" ]; then
  expect_failure "install.sh refuses a trailing-slash DEST through a symlink" \
    env HERMES_HOME="$sh_tslash_base/link/" bash "$ROOT/install.sh" --target hermes --copy
  if [ ! -e "$sh_tslash_victim/agents" ] \
    && grep -qxF 'victim content' "$sh_tslash_victim/keep.txt"; then
    ok "install.sh trailing-slash symlink leaves victim unchanged"
  else
    bad "install.sh trailing-slash symlink leaves victim unchanged"
  fi
else
  printf 'PENDING: install.sh trailing-slash check requires a physical symlink\n'
  fi
fi

sh_tslash_ok="$tmp/sh-tslash-ok/"
expect_success "install.sh accepts a trailing slash on a real DEST" \
  env HERMES_HOME="$sh_tslash_ok" bash "$ROOT/install.sh" --target hermes --copy
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$tmp/sh-tslash-ok/agents" "$tmp/sh-tslash-ok/skills" "$tmp/sh-tslash-ok/commands" >/dev/null 2>&1; then
  bad "install.sh trailing-slash DEST left an unresolved placeholder"
else
  ok "install.sh trailing-slash DEST left no unresolved placeholder"
fi

sh_hash_home="$tmp/sh-hash#test"
expect_success "install.sh resolves placeholders when DEST contains a hash" \
  env HERMES_HOME="$sh_hash_home" bash "$ROOT/install.sh" --target hermes --copy
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$sh_hash_home/agents" "$sh_hash_home/skills" "$sh_hash_home/commands" >/dev/null 2>&1; then
  bad "install.sh hash DEST left an unresolved placeholder"
else
  ok "install.sh hash DEST left no unresolved placeholder"
fi
if grep -rlF "$sh_hash_home" "$sh_hash_home/agents" >/dev/null 2>&1; then
  ok "install.sh hash DEST resolves to a literal path"
else
  bad "install.sh hash DEST resolves to a literal path"
fi

sh_nl_home="$tmp/sh-newline$(printf '\n')test"
expect_success "install.sh resolves placeholders when DEST contains a newline" \
  env HERMES_HOME="$sh_nl_home" bash "$ROOT/install.sh" --target hermes --copy
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$sh_nl_home/agents" "$sh_nl_home/skills" "$sh_nl_home/commands" >/dev/null 2>&1; then
  bad "install.sh newline DEST left an unresolved placeholder"
else
  ok "install.sh newline DEST left no unresolved placeholder"
fi

# A fresh Codex session is exercised through the real bootstrap and a minimal marketplace
# fake. The fake installs the candidate's native command and skills; the bootstrap must then
# generate its own Sefi profiles, matching the native CLI seam without contacting a registry.
codex_bin="$tmp/codex-bin"
codex_home="$tmp/codex-home"
mkdir -p "$codex_bin" "$codex_home"
cat >"$codex_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
marketplace_state="$CODEX_HOME/marketplaces.json"
native_path() {
  cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
}
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
if [ "$1 $2 $3" = 'plugin marketplace list' ]; then
  if [ -n "${CODEX_TEST_MARKETPLACE_OVERRIDE:-}" ]; then
    printf '%s\n' "$CODEX_TEST_MARKETPLACE_OVERRIDE"
  elif [ -f "$marketplace_state" ]; then
    cat "$marketplace_state"
  else
    printf '{"marketplaces":[]}\n'
  fi
  exit 0
fi
if [ "$1 $2 $3" = 'plugin marketplace add' ]; then
  marketplace_root="${CODEX_TEST_MARKETPLACE_ROOT:-$(dirname "$CODEX_TEST_SOURCE")}"
  marketplace_source="${CODEX_TEST_MARKETPLACE_SOURCE:-${4:-}}"
  marketplace_root="$(native_path "$marketplace_root")"
  case "$marketplace_source" in *://*) ;; *) marketplace_source="$(native_path "$marketplace_source")" ;; esac
  mkdir -p "$CODEX_HOME"
  if [ "${CODEX_TEST_LOCAL_MARKETPLACE_SHAPE:-}" = 1 ]; then
    printf '{"marketplaces":[{"name":"sefi-agents","root":"%s"}]}\n' "$(json_escape "$marketplace_root")" >"$marketplace_state"
  else
    printf '{"marketplaces":[{"name":"sefi-agents","root":"%s","marketplaceSource":{"sourceType":"local","source":"%s"}}]}\n' "$(json_escape "$marketplace_root")" "$(json_escape "$marketplace_source")" >"$marketplace_state"
  fi
  exit 0
fi
if [ "$1 $2 $3" = 'plugin marketplace upgrade' ]; then exit 0; fi
if [ "$1 $2 $3" = 'plugin add sefi-core@sefi-agents' ]; then
  plugin="${CODEX_TEST_PLUGIN_PATH:-$CODEX_TEST_SOURCE}"
  if [ "$plugin" != "$CODEX_TEST_SOURCE" ]; then
    mkdir -p "$plugin"
    cp -R "$CODEX_TEST_SOURCE/." "$plugin/"
  fi
  exit 0
fi
if [ "$1 $2 $3" = 'plugin list --json' ]; then
  marketplace_source="${CODEX_TEST_MARKETPLACE_SOURCE:-$(dirname "$CODEX_TEST_SOURCE")}"
  plugin="${CODEX_TEST_PLUGIN_PATH:-$CODEX_TEST_SOURCE}"
  plugin="$(native_path "$plugin")"
  case "$marketplace_source" in *://*) ;; *) marketplace_source="$(native_path "$marketplace_source")" ;; esac
  printf '{"installed":[{"pluginId":"sefi-core@sefi-agents","marketplaceName":"sefi-agents","source":{"source":"local","path":"%s"},"marketplaceSource":{"sourceType":"local","source":"%s"}}]}\n' "$(json_escape "$plugin")" "$(json_escape "$marketplace_source")"
  exit 0
fi
exit 64
EOF
chmod +x "$codex_bin/codex"
expect_success "Codex fresh session bootstrap retains audit invocation and auditor" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
if [ -f "$CORE/commands/audit.md" ] \
  && [ -f "$CORE/skills/systems-audit/SKILL.md" ] \
  && grep -Fq '/sefi:audit' "$CORE/commands/audit.md" \
  && python - "$CORE/agents/systems-auditor.md" "$codex_home/agents/systems-auditor.toml" <<'PY'
import re
import sys
import tomllib
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
expected = re.split(r"^---\s*$", source, maxsplit=2, flags=re.MULTILINE)[2].lstrip("\r\n")
profile = tomllib.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if profile.get("name") != "systems-auditor" or profile.get("developer_instructions") != expected:
    raise SystemExit("Systems Auditor profile differs from its installed plugin source")
PY
then
  ok "Codex fresh session exposes audit invocation and Systems Auditor profile"
else
  bad "Codex fresh session exposes audit invocation and Systems Auditor profile"
fi

codex_agents_link_home="$tmp/codex-agents-link"
codex_agents_link_target="$tmp/codex-agents-link-target"
mkdir -p "$codex_agents_link_home" "$codex_agents_link_target"
if ln -s "$codex_agents_link_target" "$codex_agents_link_home/agents" 2>/dev/null \
  && [ -L "$codex_agents_link_home/agents" ]; then
  expect_failure "Codex rejects a symlinked agents directory" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_agents_link_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ ! -e "$codex_agents_link_target/systems-auditor.toml" ]; then
    ok "Codex symlinked agents directory leaves its target unchanged"
  else
    bad "Codex symlinked agents directory leaves its target unchanged"
  fi
else
  printf 'PENDING: Codex agents-directory symlink check requires a physical symlink\n'
fi

codex_profile_link_home="$tmp/codex-profile-link"
codex_profile_link_target="$tmp/codex-profile-link-target"
mkdir -p "$codex_profile_link_home/agents" "$codex_profile_link_target"
printf 'unrelated content\n' > "$codex_profile_link_target/keep.txt"
if ln -s "$codex_profile_link_target/dangling-profile.toml" "$codex_profile_link_home/agents/systems-auditor.toml" 2>/dev/null \
  && [ -L "$codex_profile_link_home/agents/systems-auditor.toml" ]; then
  expect_failure "Codex rejects a dangling Sefi profile symlink" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_profile_link_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ ! -e "$codex_profile_link_target/dangling-profile.toml" ] \
    && grep -qxF 'unrelated content' "$codex_profile_link_target/keep.txt"; then
    ok "Codex dangling profile symlink leaves unrelated targets unchanged"
  else
    bad "Codex dangling profile symlink leaves unrelated targets unchanged"
  fi
else
  printf 'PENDING: Codex profile-symlink check requires a physical symlink\n'
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: Codex parent-symlink check needs a fixture temp outside $HOME\n'
else
  codex_parent_base="$outside_home_temp/codex-parent-base"
  codex_parent_victim="$outside_home_temp/codex-parent-victim"
  mkdir -p "$codex_parent_base" "$codex_parent_victim"
  printf 'victim content\n' > "$codex_parent_victim/keep.txt"
  if ln -s "$codex_parent_victim" "$codex_parent_base/link" 2>/dev/null \
    && [ -L "$codex_parent_base/link" ]; then
    expect_failure "Codex refuses a symlinked CODEX_HOME parent" \
      env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_parent_base/link/subdir" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
    # The fake CLI creates victim/subdir/marketplaces.json before the gate, so only
    # installer-owned paths (agents/, AGENTS.md) prove the installer wrote nothing.
    if [ ! -e "$codex_parent_victim/subdir/agents" ] \
      && [ ! -e "$codex_parent_victim/subdir/AGENTS.md" ] \
      && grep -qxF 'victim content' "$codex_parent_victim/keep.txt"; then
      ok "Codex symlinked parent leaves victim unchanged"
    else
      bad "Codex symlinked parent leaves victim unchanged"
    fi
  else
    printf 'PENDING: Codex parent-symlink check requires a physical symlink\n'
  fi
fi

# Behavioral replacement for the deleted grep on 'refusing symlinked agent profile'.
# That grep counted a string that also lives in the comments, so deleting both guard
# blocks left it passing. What the guards actually buy is refused EARLY: the profile loop
# runs before the bootstrap block is written, so a run that refuses a symlinked profile
# must leave AGENTS.md unwritten. Delete the loop guard and the run walks past the loop,
# writes the block, and only trips the later staged-copy guard -- which the AGENTS.md
# assertion here catches. The victim is a VALID profile carrying developer_instructions,
# so a run that reads it through the link republishes its marker instead of failing to
# parse, which is what makes the "nothing published" assertion guard-sensitive too.
codex_guard_marker='victim-owned-developer-instructions'
codex_guard_home="$tmp/codex-profile-guard-home"
codex_guard_victim="$tmp/codex-profile-guard-victim.toml"
mkdir -p "$codex_guard_home/agents"
printf 'name = "systems-auditor"\ndescription = "victim"\ndeveloper_instructions = "%s"\n' \
  "$codex_guard_marker" > "$codex_guard_victim"
if ln -s "$codex_guard_victim" "$codex_guard_home/agents/systems-auditor.toml" 2>/dev/null \
  && [ -L "$codex_guard_home/agents/systems-auditor.toml" ]; then
  expect_failure "Codex refuses a symlinked Sefi profile" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_guard_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ -L "$codex_guard_home/agents/systems-auditor.toml" ] \
    && grep -qF "$codex_guard_marker" "$codex_guard_victim" \
    && ! grep -q '^model = ' "$codex_guard_victim" \
    && [ -z "$(grep -rlF "$codex_guard_marker" "$codex_guard_home/agents" 2>/dev/null || true)" ] \
    && [ ! -e "$codex_guard_home/AGENTS.md" ]; then
    ok "Codex refuses a symlinked profile before writing anything else"
  else
    bad "Codex refuses a symlinked profile before writing anything else"
  fi
else
  printf 'PENDING: Codex profile-guard ordering check requires a physical symlink\n'
fi

# A symlinked AGENTS.md is refused, never followed. A link to a REGULAR FILE would be read
# by the block-strip awk and then replaced outright by the staged mv, destroying the link
# the user maintains; a link to a DIRECTORY makes that same mv move the staged block
# inside the linked directory and leave the link in place, so the install would print
# success while publishing into an unrelated tree. Both shapes are asserted.
codex_mdlink_home="$tmp/codex-agents-md-file-home"
codex_mdlink_victim="$tmp/codex-agents-md-file-victim.md"
mkdir -p "$codex_mdlink_home"
printf 'user-owned agents notes\n' > "$codex_mdlink_victim"
if ln -s "$codex_mdlink_victim" "$codex_mdlink_home/AGENTS.md" 2>/dev/null \
  && [ -L "$codex_mdlink_home/AGENTS.md" ]; then
  expect_failure "Codex refuses an AGENTS.md symlinked to a regular file" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_mdlink_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ -L "$codex_mdlink_home/AGENTS.md" ] \
    && grep -qxF 'user-owned agents notes' "$codex_mdlink_victim" \
    && ! grep -q 'sefi-agents:codex-bootstrap:start' "$codex_mdlink_victim"; then
    ok "Codex leaves a symlinked AGENTS.md and its file target unmodified"
  else
    bad "Codex leaves a symlinked AGENTS.md and its file target unmodified"
  fi
else
  printf 'PENDING: Codex AGENTS.md file-symlink check requires a physical symlink\n'
fi

codex_mddirlink_home="$tmp/codex-agents-md-dir-home"
codex_mddirlink_victim="$tmp/codex-agents-md-dir-target"
mkdir -p "$codex_mddirlink_home" "$codex_mddirlink_victim"
printf 'unrelated directory content\n' > "$codex_mddirlink_victim/keep.txt"
if ln -s "$codex_mddirlink_victim" "$codex_mddirlink_home/AGENTS.md" 2>/dev/null \
  && [ -L "$codex_mddirlink_home/AGENTS.md" ]; then
  expect_failure "Codex refuses an AGENTS.md symlinked to a directory" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_mddirlink_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ -L "$codex_mddirlink_home/AGENTS.md" ] \
    && [ ! -e "$codex_mddirlink_victim/AGENTS.md" ] \
    && grep -qxF 'unrelated directory content' "$codex_mddirlink_victim/keep.txt"; then
    ok "Codex publishes no bootstrap block into a directory symlinked as AGENTS.md"
  else
    bad "Codex publishes no bootstrap block into a directory symlinked as AGENTS.md"
  fi
else
  printf 'PENDING: Codex AGENTS.md directory-symlink check requires a physical symlink\n'
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: Codex existing-subdir check needs a fixture temp outside $HOME\n'
else
  codex_existing_base="$outside_home_temp/codex-existing-base"
  codex_existing_victim="$outside_home_temp/codex-existing-victim"
  mkdir -p "$codex_existing_base" "$codex_existing_victim/subdir"
  printf 'victim content\n' > "$codex_existing_victim/keep.txt"
  if ln -s "$codex_existing_victim" "$codex_existing_base/link" 2>/dev/null \
    && [ -L "$codex_existing_base/link" ]; then
    expect_failure "Codex refuses an existing subdir via a symlinked parent" \
      env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_existing_base/link/subdir" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
    if [ ! -e "$codex_existing_victim/subdir/agents" ] \
      && grep -qxF 'victim content' "$codex_existing_victim/keep.txt"; then
      ok "Codex existing subdir via symlinked parent leaves victim unchanged"
    else
      bad "Codex existing subdir via symlinked parent leaves victim unchanged"
    fi
  else
    printf 'PENDING: Codex existing-subdir check requires a physical symlink\n'
  fi
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: Codex trailing-slash check needs a fixture temp outside $HOME\n'
else
  codex_tslash_base="$outside_home_temp/codex-tslash-base"
  codex_tslash_victim="$outside_home_temp/codex-tslash-victim"
  mkdir -p "$codex_tslash_base" "$codex_tslash_victim"
  printf 'victim content\n' > "$codex_tslash_victim/keep.txt"
  if ln -s "$codex_tslash_victim" "$codex_tslash_base/link" 2>/dev/null \
    && [ -L "$codex_tslash_base/link" ]; then
    expect_failure "Codex refuses a trailing-slash CODEX_HOME through a symlink" \
      env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_tslash_base/link/" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
    if [ ! -e "$codex_tslash_victim/agents" ] \
      && grep -qxF 'victim content' "$codex_tslash_victim/keep.txt"; then
      ok "Codex trailing-slash symlink leaves victim unchanged"
    else
      bad "Codex trailing-slash symlink leaves victim unchanged"
    fi
  else
    printf 'PENDING: Codex trailing-slash check requires a physical symlink\n'
  fi
fi

expect_success "Codex accepts a trailing slash on a real CODEX_HOME" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$tmp/codex-trailing/" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
if [ -f "$tmp/codex-trailing/agents/systems-auditor.toml" ] \
  && [ -f "$tmp/codex-trailing/AGENTS.md" ]; then
  ok "Codex trailing-slash CODEX_HOME installs profiles"
else
  bad "Codex trailing-slash CODEX_HOME installs profiles"
fi

# CODEX_HOME is resolved through the same path-safety helpers as the other two
# installers, so a destination built from a delimiter character has to install
# cleanly rather than corrupt the generated block or the profile write.
for codex_delim in amp hash newline; do
  case "$codex_delim" in
    amp) codex_delim_home="$tmp/codex-amp&test" ;;
    hash) codex_delim_home="$tmp/codex-hash#test" ;;
    newline) codex_delim_home="$tmp/codex-newline$(printf '\n')test" ;;
  esac
  expect_success "Codex accepts a $codex_delim CODEX_HOME" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_delim_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ -f "$codex_delim_home/AGENTS.md" ] \
    && grep -qF 'sefi-agents:codex-bootstrap:start' "$codex_delim_home/AGENTS.md" \
    && [ -f "$codex_delim_home/agents/systems-auditor.toml" ]; then
    ok "Codex $codex_delim CODEX_HOME installs the block and profiles"
  else
    bad "Codex $codex_delim CODEX_HOME installs the block and profiles"
  fi
done

codex_live_home="$tmp/codex-live-profile"
codex_live_victim="$tmp/codex-live-victim.toml"
mkdir -p "$codex_live_home/agents"
printf 'live victim profile\n' > "$codex_live_victim"
if ln -s "$codex_live_victim" "$codex_live_home/agents/systems-auditor.toml" 2>/dev/null \
  && [ -L "$codex_live_home/agents/systems-auditor.toml" ]; then
  expect_failure "Codex refuses a live Sefi profile symlink" \
    env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_live_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if grep -qxF 'live victim profile' "$codex_live_victim" \
    && [ -L "$codex_live_home/agents/systems-auditor.toml" ]; then
    ok "Codex live profile symlink leaves its target unmodified"
  else
    bad "Codex live profile symlink leaves its target unmodified"
  fi
else
  printf 'PENDING: Codex live-profile check requires a physical symlink\n'
fi

# Behavioral replacement for a grep assertion on '.sefi-agent-new.'. Grepping the
  # staging prefix cannot fail when the guarded code is deleted and only the comment
  # survives. The idempotence assertion below is the behavioural form of the same
  # claim: a profile produced by stage-then-mv carries exactly one model line and one
  # reasoning line after any number of re-runs, and the installer leaves neither a
  # staging file nor a symlink behind. A direct write at the live path, or a lost
  # re-check, changes what lands there.
codex_stage_home="$tmp/codex-staged-profiles"
expect_success "Codex re-runs cleanly over its own staged profiles" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_stage_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
expect_success "Codex applies the model policy exactly once on re-run" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$codex_stage_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
codex_stage_bad=""
for codex_stage_profile in "$codex_stage_home"/agents/*.toml; do
  [ -f "$codex_stage_profile" ] || continue
  [ -L "$codex_stage_profile" ] && codex_stage_bad="$codex_stage_bad symlink:$codex_stage_profile"
  codex_stage_models="$(grep -c '^model = ' "$codex_stage_profile" || true)"
  codex_stage_efforts="$(grep -c '^model_reasoning_effort = ' "$codex_stage_profile" || true)"
  [ "$codex_stage_models" = "1" ] || codex_stage_bad="$codex_stage_bad models:$codex_stage_models"
  [ "$codex_stage_efforts" = "1" ] || codex_stage_bad="$codex_stage_bad efforts:$codex_stage_efforts"
done
codex_stage_leftover="$(find "$codex_stage_home/agents" -maxdepth 1 -name '.sefi-agent-*' -print -quit 2>/dev/null || true)"
if [ -z "$codex_stage_bad" ] && [ -z "$codex_stage_leftover" ]; then
  ok "Codex leaves one model policy per profile and no staging leftover"
else
  printf 'FAIL: Codex leaves one model policy per profile and no staging leftover (%s leftover=%s)\n' \
    "$codex_stage_bad" "$codex_stage_leftover" >&2
  fail=1
fi

# Codex's actual local marketplace list contains the candidate root but omits
# marketplaceSource.source until after the plugin has been installed.
expect_success "Codex candidate accepts the local marketplace root-only JSON shape" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$tmp/codex-local-marketplace-shape" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" CODEX_TEST_LOCAL_MARKETPLACE_SHAPE=1 bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"

# A matching source string elsewhere in the document cannot authorize a colliding named
# marketplace record. The installer must reject it before any plugin code is invoked.
wrong_marketplaces="{\"marketplaces\":[{\"name\":\"sefi-agents\",\"root\":\"$tmp/not-sefi-agents\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$tmp/not-sefi-agents\"}},{\"name\":\"unrelated\",\"root\":\"$ROOT\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$ROOT\"}}]}"
expect_failure "Codex rejects a colliding marketplace despite an unrelated expected source" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$tmp/codex-wrong-marketplace" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_OVERRIDE="$wrong_marketplaces" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"

# Candidate mode must execute only the selected checkout's plugin tree, never an equally
# shaped copy that an untrusted CLI record points outside that checkout.
outside_plugin="$tmp/outside-candidate/sefi-core"
expect_failure "Codex rejects a candidate plugin source outside the selected checkout" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$tmp/codex-outside-candidate" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" CODEX_TEST_PLUGIN_PATH="$outside_plugin" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"

# The ordinary public path still accepts an installed source only when it is physically
# nested under the marketplace that reports the expected remote origin.
remote_marketplace="$tmp/remote-marketplace"
remote_plugin="$remote_marketplace/plugins/sefi-core"
mkdir -p "$remote_plugin"
cp -R "$CORE/." "$remote_plugin/"
expect_success "Codex remote install verifies the expected marketplace and plugin source" \
  env PATH="$codex_bin:$PATH" CODEX_HOME="$tmp/codex-remote" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$remote_marketplace" CODEX_TEST_MARKETPLACE_SOURCE="https://github.com/xsefirosus/sefi-agents.git" CODEX_TEST_PLUGIN_PATH="$remote_plugin" bash "$ROOT/install-codex.sh"

# OpenCode copies the shipped skills tree after applying its existing agent transform.
oc_home="$tmp/opencode"
expect_success "opencode fresh install includes systems-audit" env OPENCODE_HOME="$oc_home" bash "$OPENCODE_INSTALL"
if [ -f "$oc_home/skills/systems-audit/SKILL.md" ] && [ -f "$oc_home/skills/systems-audit/references/report-contract.md" ]; then
  ok "OpenCode installed systems-audit files"
else
  bad "OpenCode installed systems-audit files"
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: OpenCode parent-symlink check needs a fixture temp outside $HOME\n'
else
  oc_parent_base="$outside_home_temp/oc-parent-base"
  oc_parent_victim="$outside_home_temp/oc-parent-victim"
  mkdir -p "$oc_parent_base" "$oc_parent_victim"
  printf 'victim content\n' > "$oc_parent_victim/keep.txt"
  if ln -s "$oc_parent_victim" "$oc_parent_base/link" 2>/dev/null \
    && [ -L "$oc_parent_base/link" ]; then
    expect_failure "OpenCode refuses a symlinked destination parent" \
      env OPENCODE_HOME="$oc_parent_base/link/subdir" bash "$OPENCODE_INSTALL"
    if [ ! -e "$oc_parent_victim/subdir" ] \
      && [ ! -e "$oc_parent_victim/agents" ] \
      && grep -qxF 'victim content' "$oc_parent_victim/keep.txt"; then
      ok "OpenCode symlinked parent leaves victim unchanged"
    else
      bad "OpenCode symlinked parent leaves victim unchanged"
    fi
  else
    printf 'PENDING: OpenCode parent-symlink check requires a physical symlink\n'
  fi
fi

oc_amp_home="$tmp/oc-amp&test"
expect_success "OpenCode resolves placeholders when DEST contains ampersand" env OPENCODE_HOME="$oc_amp_home" bash "$OPENCODE_INSTALL"
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$oc_amp_home/agents" "$oc_amp_home/skills" "$oc_amp_home/commands" >/dev/null 2>&1; then
  bad "OpenCode ampersand DEST left an unresolved placeholder"
else
  ok "OpenCode ampersand DEST left no unresolved placeholder"
fi
if grep -rlF "$oc_amp_home" "$oc_amp_home/agents" >/dev/null 2>&1; then
  ok "OpenCode ampersand DEST resolves to a literal path"
else
  bad "OpenCode ampersand DEST resolves to a literal path"
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: OpenCode existing-subdir check needs a fixture temp outside $HOME\n'
else
  oc_existing_base="$outside_home_temp/oc-existing-base"
  oc_existing_victim="$outside_home_temp/oc-existing-victim"
  mkdir -p "$oc_existing_base" "$oc_existing_victim/subdir"
  printf 'victim content\n' > "$oc_existing_victim/keep.txt"
  if ln -s "$oc_existing_victim" "$oc_existing_base/link" 2>/dev/null \
    && [ -L "$oc_existing_base/link" ]; then
    expect_failure "OpenCode refuses an existing subdir via a symlinked parent" \
      env OPENCODE_HOME="$oc_existing_base/link/subdir" bash "$OPENCODE_INSTALL"
    if [ ! -e "$oc_existing_victim/subdir/agents" ] \
      && grep -qxF 'victim content' "$oc_existing_victim/keep.txt"; then
      ok "OpenCode existing subdir via symlinked parent leaves victim unchanged"
    else
      bad "OpenCode existing subdir via symlinked parent leaves victim unchanged"
    fi
  else
    printf 'PENDING: OpenCode existing-subdir check requires a physical symlink\n'
  fi
fi

if [ -z "$outside_home_temp" ]; then
  printf 'PENDING: OpenCode trailing-slash check needs a fixture temp outside $HOME\n'
else
  oc_tslash_base="$outside_home_temp/oc-tslash-base"
  oc_tslash_victim="$outside_home_temp/oc-tslash-victim"
  mkdir -p "$oc_tslash_base" "$oc_tslash_victim"
  printf 'victim content\n' > "$oc_tslash_victim/keep.txt"
  if ln -s "$oc_tslash_victim" "$oc_tslash_base/link" 2>/dev/null \
    && [ -L "$oc_tslash_base/link" ]; then
    expect_failure "OpenCode refuses a trailing-slash DEST through a symlink" \
      env OPENCODE_HOME="$oc_tslash_base/link/" bash "$OPENCODE_INSTALL"
    if [ ! -e "$oc_tslash_victim/agents" ] \
      && grep -qxF 'victim content' "$oc_tslash_victim/keep.txt"; then
      ok "OpenCode trailing-slash symlink leaves victim unchanged"
    else
      bad "OpenCode trailing-slash symlink leaves victim unchanged"
    fi
  else
    printf 'PENDING: OpenCode trailing-slash check requires a physical symlink\n'
  fi
fi

oc_tslash_ok="$tmp/oc-trailing/"
expect_success "OpenCode accepts a trailing slash on a real DEST" env OPENCODE_HOME="$oc_tslash_ok" bash "$OPENCODE_INSTALL"
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$tmp/oc-trailing/agents" "$tmp/oc-trailing/skills" "$tmp/oc-trailing/commands" >/dev/null 2>&1; then
  bad "OpenCode trailing-slash DEST left an unresolved placeholder"
else
  ok "OpenCode trailing-slash DEST left no unresolved placeholder"
fi

oc_hash_home="$tmp/oc-hash#test"
expect_success "OpenCode resolves placeholders when DEST contains a hash" env OPENCODE_HOME="$oc_hash_home" bash "$OPENCODE_INSTALL"
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$oc_hash_home/agents" "$oc_hash_home/skills" "$oc_hash_home/commands" >/dev/null 2>&1; then
  bad "OpenCode hash DEST left an unresolved placeholder"
else
  ok "OpenCode hash DEST left no unresolved placeholder"
fi
if grep -rlF "$oc_hash_home" "$oc_hash_home/agents" >/dev/null 2>&1; then
  ok "OpenCode hash DEST resolves to a literal path"
else
  bad "OpenCode hash DEST resolves to a literal path"
fi

oc_nl_home="$tmp/oc-newline$(printf '\n')test"
expect_success "OpenCode resolves placeholders when DEST contains a newline" env OPENCODE_HOME="$oc_nl_home" bash "$OPENCODE_INSTALL"
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$oc_nl_home/agents" "$oc_nl_home/skills" "$oc_nl_home/commands" >/dev/null 2>&1; then
  bad "OpenCode newline DEST left an unresolved placeholder"
else
  ok "OpenCode newline DEST left no unresolved placeholder"
fi

oc_swap_home="$tmp/oc-swap"
oc_swap_victim="$tmp/oc-swap-victim.md"
expect_success "OpenCode prepares a home for the swapped-profile check" env OPENCODE_HOME="$oc_swap_home" bash "$OPENCODE_INSTALL"
printf 'live victim agent\n' > "$oc_swap_victim"
rm -f "$oc_swap_home/agents/systems-auditor.md"
if ln -s "$oc_swap_victim" "$oc_swap_home/agents/systems-auditor.md" 2>/dev/null \
  && [ -L "$oc_swap_home/agents/systems-auditor.md" ]; then
  expect_failure "OpenCode refuses a swapped-in agent symlink without force" env OPENCODE_HOME="$oc_swap_home" bash "$OPENCODE_INSTALL"
  if grep -qxF 'live victim agent' "$oc_swap_victim" \
    && [ -L "$oc_swap_home/agents/systems-auditor.md" ]; then
    ok "OpenCode swapped agent symlink leaves its target unmodified"
  else
    bad "OpenCode swapped agent symlink leaves its target unmodified"
  fi
  expect_success "OpenCode force install over an agent symlink keeps the target" env OPENCODE_HOME="$oc_swap_home" bash "$OPENCODE_INSTALL" --force
  if grep -qxF 'live victim agent' "$oc_swap_victim" \
    && [ -f "$oc_swap_home/agents/systems-auditor.md" ] \
    && [ ! -L "$oc_swap_home/agents/systems-auditor.md" ]; then
    ok "OpenCode forced agent write never follows the swapped symlink"
  else
    bad "OpenCode forced agent write never follows the swapped symlink"
  fi
else
  printf 'PENDING: OpenCode swapped-profile check requires a physical symlink\n'
fi

# Behavioral replacement for a grep assertion on 'that reappeared'. The string survives
  # in a comment even if the re-check and the staged move are both deleted, so this
  # asserts the result the re-check protects: after a forced install over a symlinked
  # destination, the victim's bytes are untouched AND the destination holds the fully
  # transformed profile (permission block, resolved placeholder) as a regular file --
  # which is only true if the staged content really was moved into place.
oc_recheck_victim="$tmp/oc-recheck-victim.md"
oc_recheck_home="$tmp/oc-recheck-home"
expect_success "OpenCode prepares a home for the re-check assertions" env OPENCODE_HOME="$oc_recheck_home" bash "$OPENCODE_INSTALL"
printf 'recheck victim agent\n' > "$oc_recheck_victim"
rm -f "$oc_recheck_home/agents/systems-auditor.md"
if ln -s "$oc_recheck_victim" "$oc_recheck_home/agents/systems-auditor.md" 2>/dev/null \
  && [ -L "$oc_recheck_home/agents/systems-auditor.md" ]; then
  expect_success "OpenCode force install over an agent symlink moves staged content in" \
    env OPENCODE_HOME="$oc_recheck_home" bash "$OPENCODE_INSTALL" --force
  oc_recheck_file="$oc_recheck_home/agents/systems-auditor.md"
  if grep -qxF 'recheck victim agent' "$oc_recheck_victim" \
    && [ -f "$oc_recheck_file" ] && [ ! -L "$oc_recheck_file" ] \
    && grep -q '^permission:' "$oc_recheck_file" \
    && ! grep -q '${CLAUDE_PLUGIN_ROOT}' "$oc_recheck_file"; then
    ok "OpenCode staged agent content reaches the destination without touching the link target"
  else
    bad "OpenCode staged agent content reaches the destination without touching the link target"
  fi
  # A second file proves the re-check does not abort the whole run on an unrelated
  # entry: the install must still finish every remaining profile.
  if [ -f "$oc_recheck_home/agents/sefi-agents.md" ] \
    && grep -q '^permission:' "$oc_recheck_home/agents/sefi-agents.md"; then
    ok "OpenCode continues past a re-checked target and transforms the remaining profiles"
  else
    bad "OpenCode continues past a re-checked target and transforms the remaining profiles"
  fi
else
  printf 'PENDING: OpenCode staged-content re-check requires a physical symlink\n'
fi

# --- Directory-swap races (NEW-2) -----------------------------------------------------
# The directory gate runs once, before any write. These cases exploit that gap the
# way the reviewer's did: the subtree passes the gate, then is replaced by a symlink to
# an attacker-controlled directory before the installer writes into it. The swap is
# triggered deterministically by a shim on mktemp -- the first filesystem call at each
# write site -- so no timing assumption is involved.
#
# A pre-existing file in the victim directory is the canary: an installer that follows
# the swapped link installs profiles over the attacker's directory instead of aborting.
#
# Every case here needs a real symlink. On a host without one (MSYS without symlink
# privilege) they are reported PENDING, the same fail-closed convention the rest of
# this file uses, rather than passing vacuously.
symlink_probe_dir="$tmp/symlink-capability"
mkdir -p "$symlink_probe_dir"
if ln -s "$symlink_probe_dir" "$symlink_probe_dir/link" 2>/dev/null \
  && [ -L "$symlink_probe_dir/link" ]; then
  symlinks_supported=1
else
  symlinks_supported=0
  printf 'PENDING: directory-swap races require a physical symlink\n'
fi

make_swap_shim() {
  # make_swap_shim <shim-dir> <victim-dir> <staging-template> <dir-to-swap>
  # The real mktemp is resolved by absolute path at fixture time and the shim execs
  # that, never a bare "mktemp": the shim directory is prepended to PATH, so a bare
  # name would resolve back to the shim and fork-bomb the fixture.
  #
  # The template is matched against EVERY argument, not against $1, because mktemp takes
  # its options first: install.sh asks for `mktemp -d "$DEST/.sefi-agents.XXXXXX"`, where
  # the template is the SECOND argument, while the other two installers use a bare
  # single-argument form. A $1-only match could never fire for the -d call, so the swap
  # never happened and the case asserted nothing about the guard it was written for.
  local real_mktemp
  real_mktemp="$(command -v mktemp)"
  cat >"$1/mktemp" <<SHIM
#!/usr/bin/env bash
# Swap a gated directory for a symlink to an attacker-controlled victim, once, at the
# exact moment the installer asks for a staging file -- then behave like real mktemp.
swap_now=0
for swap_arg in "\$@"; do
  [ "\$swap_arg" = "$3" ] && swap_now=1
done
if [ "\$swap_now" -eq 1 ] && [ ! -e "$2/.swap-done" ]; then
  : > "$2/.swap-done"
  rm -rf "$4"
  ln -s "$2" "$4" 2>/dev/null || true
fi
exec "$real_mktemp" "\$@"
SHIM
  chmod +x "$1/mktemp"
}

# The shim's match is the whole point of the cases below, so it is asserted on its own,
# against the real mktemp, in both shapes the installers use: `mktemp -d TEMPLATE` and
# `mktemp TEMPLATE`. The swap's own marker file is the evidence, and the shim's rm/ln are
# harmless no-ops here, so this holds on a host with no symlink privilege at all -- unlike
# the race cases that need one.
swap_probe_bin="$tmp/swap-shim-probe-bin"
swap_probe_dest="$tmp/swap-shim-probe-dest"
mkdir -p "$swap_probe_bin" "$swap_probe_dest"
for swap_probe_form in dash_d bare; do
  swap_probe_victim="$tmp/swap-shim-probe-victim-$swap_probe_form"
  mkdir -p "$swap_probe_victim"
  if [ "$swap_probe_form" = dash_d ]; then
    make_swap_shim "$swap_probe_bin" "$swap_probe_victim" \
      "$swap_probe_dest/.sefi-agents.XXXXXX" "$tmp/swap-shim-probe-swap-$swap_probe_form"
    env PATH="$swap_probe_bin:$PATH" mktemp -d "$swap_probe_dest/.sefi-agents.XXXXXX" >/dev/null
  else
    make_swap_shim "$swap_probe_bin" "$swap_probe_victim" \
      "$swap_probe_dest/.sefi-agent.XXXXXX" "$tmp/swap-shim-probe-swap-$swap_probe_form"
    env PATH="$swap_probe_bin:$PATH" mktemp "$swap_probe_dest/.sefi-agent.XXXXXX" >/dev/null
  fi
done
if [ -e "$tmp/swap-shim-probe-victim-dash_d/.swap-done" ] \
  && [ -e "$tmp/swap-shim-probe-victim-bare/.swap-done" ]; then
  ok "the swap shim fires on both the mktemp -d and the bare staging-template form"
else
  bad "the swap shim fires on both the mktemp -d and the bare staging-template form"
fi

if [ "$symlinks_supported" -eq 1 ]; then
  codex_swap_bin="$tmp/codex-swap-bin"
  codex_swap_home="$tmp/codex-swap-home"
  codex_swap_victim="$tmp/codex-swap-victim"
  mkdir -p "$codex_swap_bin" "$codex_swap_home/agents" "$codex_swap_victim"
  printf 'attacker authorized_keys\n' > "$codex_swap_victim/authorized_keys"
  make_swap_shim "$codex_swap_bin" "$codex_swap_victim" \
    "$codex_swap_home/agents/.sefi-agent-new.XXXXXX" "$codex_swap_home/agents"
  expect_failure "Codex aborts when the gated agents dir is swapped for a symlink mid-install" \
    env PATH="$codex_swap_bin:$codex_bin:$PATH" CODEX_HOME="$codex_swap_home" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  if [ -L "$codex_swap_home/agents" ]; then
    ok "Codex confirms the swap actually landed, so the abort is not a vacuous pass"
  else
    bad "Codex confirms the swap actually landed, so the abort is not a vacuous pass"
  fi
  if grep -qxF 'attacker authorized_keys' "$codex_swap_victim/authorized_keys" \
    && [ -z "$(find "$codex_swap_victim" -name '*.toml' -print -quit 2>/dev/null || true)" ]; then
    ok "Codex writes no profile into a directory swapped in after the gate"
  else
    bad "Codex writes no profile into a directory swapped in after the gate"
  fi

  # NEW-3: the model-policy pass must never read the live profile path. The shim
  # replaces the profiles with symlinks at the moment the pass asks for its read
  # staging file -- after the !-L test, before the read. A pass that resolved the path
  # directly would pull the victim's bytes in and then republish them at the profile
  # path; a pass that stages with cp -P copies the link, fails the staged-is-regular
  # test, and aborts with the victim untouched.
  #
  # Two details make the case able to fail. The victim is a VALID profile carrying
  # developer_instructions, so a pass that read it would not trip the awk's missing-key
  # exit and abort for an unrelated reason: it would go on to publish the victim's own
  # instructions, and the marker below would turn up in the installed tree. And every
  # profile is swapped, not just the first, so the one the pass is holding when the
  # swap fires is guaranteed to be among them -- swapping only the first left the
  # result dependent on which agent the pass happened to be on.
  codex_read_bin="$tmp/codex-read-swap-bin"
  codex_read_home="$tmp/codex-read-swap-home"
  codex_read_victim="$tmp/codex-read-swap-victim.toml"
  codex_read_marker='victim-owned-developer-instructions'
  mkdir -p "$codex_read_bin" "$codex_read_home/agents"
  printf 'name = "systems-auditor"\ndescription = "victim"\nmodel = "victim-model"\nmodel_reasoning_effort = "victim-effort"\ndeveloper_instructions = "%s"\n' \
    "$codex_read_marker" > "$codex_read_victim"
  real_mktemp_for_read="$(command -v mktemp)"
  cat >"$codex_read_bin/mktemp" <<'READSHIM'
#!/usr/bin/env bash
# Replace the live profiles with symlinks to a victim, once, at the model-policy pass's
# read-staging moment -- after its !-L test has already run.
# Quoted heredoc: nothing expands at fixture time, so $profile binds to the loop below.
# Outer paths arrive via the environment (CODEX_HOME is already the install root).
read_now=0
for read_arg in "$@"; do
  [ "$read_arg" = "$CODEX_HOME/agents/.sefi-agent-read.XXXXXX" ] && read_now=1
done
if [ "$read_now" -eq 1 ] && [ ! -e "${0%/*}/.swap-done" ]; then
  : > "${0%/*}/.swap-done"
  for profile in "$CODEX_HOME"/agents/*.toml; do
    [ -f "$profile" ] || continue
    mv -- "$profile" "$profile.real"
    ln -s "$CODEX_READ_VICTIM" "$profile"
  done
fi
exec "$SEFI_REAL_MKTEMP" "$@"
READSHIM
  chmod +x "$codex_read_bin/mktemp"
  # Seed one profile so the first pass has nothing to create and the run reaches the
  # model-policy pass that this case targets.
  printf 'name = "seeded"\ndescription = "seed"\ndeveloper_instructions = "seed"\n' \
    > "$codex_read_home/agents/seeded.toml"
  expect_failure "Codex refuses to read a profile swapped for a symlink after the -L test" \
    env PATH="$codex_read_bin:$codex_bin:$PATH" CODEX_HOME="$codex_read_home" CODEX_READ_VICTIM="$codex_read_victim" SEFI_REAL_MKTEMP="$real_mktemp_for_read" CODEX_TEST_SOURCE="$CORE" CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" bash "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
  # The swap has to have landed, or the run failed for an unrelated reason and the
  # untouched-victim assertion below would be reporting nothing.
  if [ -L "$codex_read_home/agents/seeded.toml" ]; then
    ok "Codex confirms the profile swap landed, so the refusal is not a vacuous pass"
  else
    bad "Codex confirms the profile swap landed, so the refusal is not a vacuous pass"
  fi
  if [ -L "$codex_read_home/agents/seeded.toml" ] \
    && grep -qF "$codex_read_marker" "$codex_read_victim" \
    && grep -qxF 'model = "victim-model"' "$codex_read_victim" \
    && [ -z "$(grep -rlF "$codex_read_marker" "$codex_read_home/agents" 2>/dev/null || true)" ]; then
    ok "Codex never reads or republishes a profile symlinked in after the -L test"
  else
    bad "Codex never reads or republishes a profile symlinked in after the -L test"
  fi

  oc_swap_race_bin="$tmp/oc-swap-race-bin"
  oc_swap_race_home="$tmp/oc-swap-race-home"
  oc_swap_race_victim="$tmp/oc-swap-race-victim"
  mkdir -p "$oc_swap_race_bin" "$oc_swap_race_victim"
  printf 'attacker id_rsa\n' > "$oc_swap_race_victim/id_rsa"
  make_swap_shim "$oc_swap_race_bin" "$oc_swap_race_victim" \
    "$oc_swap_race_home/agents/.sefi-agent.XXXXXX" "$oc_swap_race_home/agents"
  expect_failure "OpenCode aborts when the gated agents dir is swapped for a symlink mid-install" \
    env PATH="$oc_swap_race_bin:$PATH" OPENCODE_HOME="$oc_swap_race_home" bash "$OPENCODE_INSTALL"
  if [ -L "$oc_swap_race_home/agents" ]; then
    ok "OpenCode confirms the swap actually landed, so the abort is not a vacuous pass"
  else
    bad "OpenCode confirms the swap actually landed, so the abort is not a vacuous pass"
  fi
  if grep -qxF 'attacker id_rsa' "$oc_swap_race_victim/id_rsa" \
    && [ -z "$(find "$oc_swap_race_victim" -name '*.md' -print -quit 2>/dev/null || true)" ]; then
    ok "OpenCode writes no agent profile into a directory swapped in after the gate"
  else
    bad "OpenCode writes no agent profile into a directory swapped in after the gate"
  fi

  # install.sh has the same shape. --target claude-code is the mapped strategy, so the
  # agents/ subtree is produced by materialize_mapped_agents and its staging mktemp is
  # the swap point; the flexible targets (hermes) never call it and would make this
  # assertion vacuous, so the mapped target is used deliberately.
  sh_swap_bin="$tmp/sh-swap-bin"
  sh_swap_home="$tmp/sh-swap-home"
  sh_swap_victim="$tmp/sh-swap-victim"
  mkdir -p "$sh_swap_bin" "$sh_swap_victim"
  printf 'attacker bashrc\n' > "$sh_swap_victim/bashrc"
  # install.sh stages the generated agents in a DIRECTORY under DEST itself
  # (`mktemp -d "$DEST/.sefi-agents.XXXXXX"`), not under DEST/agents, so the template
  # handed to the shim is the one install.sh really passes.
  make_swap_shim "$sh_swap_bin" "$sh_swap_victim" \
    "$sh_swap_home/.claude/.sefi-agents.XXXXXX" "$sh_swap_home/.claude/agents"
  expect_failure "install.sh aborts when the gated agents dir is swapped for a symlink mid-install" \
    env PATH="$sh_swap_bin:$PATH" HOME="$sh_swap_home" bash "$ROOT/install.sh" --target claude-code --copy --force
  if [ -L "$sh_swap_home/.claude/agents" ]; then
    ok "install.sh confirms the swap actually landed, so the abort is not a vacuous pass"
  else
    bad "install.sh confirms the swap actually landed, so the abort is not a vacuous pass"
  fi
  if grep -qxF 'attacker bashrc' "$sh_swap_victim/bashrc" \
    && [ -z "$(find "$sh_swap_victim" -name '*.md' -print -quit 2>/dev/null || true)" ]; then
    ok "install.sh writes no agent profile into a directory swapped in after the gate"
  else
    bad "install.sh writes no agent profile into a directory swapped in after the gate"
  fi

  # install.sh restores the user's own legacy profile from an EXIT trap, and the first
  # thing that restore used to do was `mkdir -p` on the profile's parent -- a write, taken
  # before any containment decision. The shim swaps the whole install root for a symlink
  # at the staging mktemp, i.e. after prepare_ has already moved the user's file into its
  # backup, so the restore has to refuse BEFORE it creates anything. Without that ordering
  # the mkdir creates a subtree inside the attacker's directory; with it, the victim
  # directory gains nothing and the user's bytes stay in the backup. The victim lives
  # outside the fixture HOME on purpose: refuse_escaped_dest accepts any destination that
  # resolves inside HOME by design, and a victim in there would be indistinguishable from
  # a legitimate dotfiles layout.
  if [ -z "$outside_home_temp" ]; then
    printf 'PENDING: install.sh legacy-restore containment check needs a fixture temp outside $HOME\n'
  else
    legacy_bin="$tmp/legacy-restore-bin"
    legacy_home="$outside_home_temp/legacy-restore-home"
    legacy_victim="$outside_home_temp/legacy-restore-victim"
    mkdir -p "$legacy_bin" "$legacy_home/.claude/agents" "$legacy_victim"
    printf 'user-owned legacy profile\n' > "$legacy_home/.claude/agents/knowledge-manager.md"
    real_mktemp_legacy="$(command -v mktemp)"
    cat >"$legacy_bin/mktemp" <<LEGACYSHIM
#!/usr/bin/env bash
# Swap the whole install root for a symlink to an attacker-controlled directory, once, at
# the moment the mapped-agents staging directory is requested -- which is after
# prepare_legacy_knowledge_manager has moved the user's file into its backup. The backup
# is carried out with the root it lives in, or the swap would destroy the very file whose
# preservation this case asserts.
legacy_now=0
for legacy_arg in "\$@"; do
  [ "\$legacy_arg" = "$legacy_home/.claude/.sefi-agents.XXXXXX" ] && legacy_now=1
done
if [ "\$legacy_now" -eq 1 ] && [ ! -e "$legacy_victim/.swap-done" ]; then
  : > "$legacy_victim/.swap-done"
  for legacy_held in "$legacy_home"/.claude/.sefi-legacy-knowledge-manager.*; do
    [ -f "\$legacy_held" ] && mv -- "\$legacy_held" "$legacy_victim/held-user-profile.md"
  done
  rm -rf -- "$legacy_home/.claude"
  ln -s "$legacy_victim" "$legacy_home/.claude" 2>/dev/null || true
fi
exec "$real_mktemp_legacy" "\$@"
LEGACYSHIM
    chmod +x "$legacy_bin/mktemp"
    expect_failure "install.sh refuses to create the legacy-restore parent through a swapped root" \
      env PATH="$legacy_bin:$PATH" HOME="$legacy_home" bash "$ROOT/install.sh" --target claude-code --copy --force
    if [ -L "$legacy_home/.claude" ] \
      && [ ! -d "$legacy_victim/agents" ] \
      && grep -qxF 'user-owned legacy profile' "$legacy_victim/held-user-profile.md"; then
      ok "install.sh creates no directory for a legacy restore under a swapped root"
    else
      bad "install.sh creates no directory for a legacy restore under a swapped root"
    fi
  fi

  # The same ordering in install-opencode.sh, which has no restore path: its four subtrees
  # are created by a single mkdir, the one write there with no per-file check after it. A
  # subtree that is already a symlink outside DEST passes refuse_escaped_dest, so the
  # containment decision has to be made explicitly. Observed behaviourally: with the check
  # the run fails at that mkdir, and without it the run skips every agent through the
  # per-file checks and still reports success.
  oc_subtree_home="$tmp/oc-subtree-symlink-home"
  oc_subtree_victim="$tmp/oc-subtree-symlink-victim"
  mkdir -p "$oc_subtree_home" "$oc_subtree_victim"
  printf 'attacker id_rsa\n' > "$oc_subtree_victim/id_rsa"
  if ln -s "$oc_subtree_victim" "$oc_subtree_home/agents" 2>/dev/null \
    && [ -L "$oc_subtree_home/agents" ]; then
    expect_failure "OpenCode refuses a symlinked agents subtree before creating it" \
      env OPENCODE_HOME="$oc_subtree_home" bash "$OPENCODE_INSTALL"
    if [ -L "$oc_subtree_home/agents" ] \
      && [ -z "$(find "$oc_subtree_victim" -mindepth 1 ! -name id_rsa -print -quit 2>/dev/null || true)" ] \
      && grep -qxF 'attacker id_rsa' "$oc_subtree_victim/id_rsa"; then
      ok "OpenCode writes no profile into a subtree symlinked before the mkdir"
    else
      bad "OpenCode writes no profile into a subtree symlinked before the mkdir"
    fi
  else
    printf 'PENDING: OpenCode subtree-symlink mkdir check requires a physical symlink\n'
  fi
fi

# --- Path-safety helper contract ---------------------------------------------------
# sefi_normalize_path and sefi_canonical_path are defined inside each installer rather
# than in a sourceable module, so a fixture cannot source them without running a whole
# install. extract_installer_function copies a shipped definition verbatim out of the
# file on disk, which means the assertions below exercise the bytes the installer
# actually executes rather than a copy that could drift from them. The extraction result
# is itself asserted, so a renamed or restructured helper fails loudly instead of
# silently skipping the check.
extract_installer_function() {
  # extract_installer_function <installer> <function-name> -- print <function-name>'s
  # shipped definition. Both helpers close with a "}" in column 1 and contain no nested
  # one, so the first column-1 "}" ends the definition.
  awk -v header="$2() {" '
    $0 == header { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$1"
}

check_helper_prints() {
  # check_helper_prints <label> <harness> <function> <input> <expected> -- the helper
  # must succeed and print exactly <expected>, byte for byte. Byte equality is the
  # contract: refuse_* compares a canonical path against a spelled one with a plain
  # string comparison, so a printable-but-different answer is a defect here.
  local label="$1" harness="$2" fn="$3" input="$4" expected="$5" out
  if out="$(bash -c 'source "$1"; "$2" "$3"' _ "$harness" "$fn" "$input" 2>&1)" \
    && [ "$out" = "$expected" ]; then
    ok "$label"
  else
    printf 'FAIL: %s\nexpected: [%s]\nactual:   [%s]\n' "$label" "$expected" "$out" >&2
    fail=1
  fi
}

check_helper_status() {
  # check_helper_status <label> <harness> <function> <expected-rc> <input> <root> --
  # the helper must exit <expected-rc>. Used for the predicates, which decide rather
  # than print, so there is no output to compare byte for byte.
  local label="$1" harness="$2" fn="$3" want="$4" input="$5" root="$6" got=0
  # The status is captured through an if, never as a bare command followed by $?:
  # under this file's `set -e` a bare non-zero command exits the whole suite, so the
  # first "expected to fail" assertion would abort the run instead of asserting.
  if bash -c 'source "$1"; "$2" "$3" "$4"' _ "$harness" "$fn" "$input" "$root" >/dev/null 2>&1; then
    got=0
  else
    got=$?
  fi
  if [ "$got" = "$want" ]; then
    ok "$label"
  else
    printf 'FAIL: %s (expected rc %s, got %s)\n' "$label" "$want" "$got" >&2
    fail=1
  fi
}

check_helper_refuses() {
  # check_helper_refuses <label> <harness> <function> <input> -- the helper must fail
  # closed: non-zero status and no output at all. A helper that printed a path for an
  # input it cannot interpret is the defect, not a tolerable warning, and a helper that
  # failed while still printing would be worse than either.
  local label="$1" harness="$2" fn="$3" input="$4" out
  if out="$(bash -c 'source "$1"; "$2" "$3"' _ "$harness" "$fn" "$input" 2>&1)" \
    && [ -n "$out" ]; then
    printf 'FAIL: %s (expected refusal, got: %s)\n' "$label" "$out" >&2
    fail=1
  else
    ok "$label"
  fi
}

# The byte-equality assertions hold only where the fixture's own temporary directory is
# its own physical spelling -- no symlinked TMPDIR, and a case-preserving filesystem.
# Where it is not (a case-insensitive store where `pwd -P` returns the on-disk spelling
# rather than the spelled one, or a TMPDIR reached through a symlink), the installers
# fail closed by design, so the assertion is reported PENDING instead of pretending the
# machine is Linux. That is documented fail-closed portability, not a silent change.
fixture_pwd="$PWD"
helper_root="$tmp/path-helper-root"
mkdir -p "$helper_root/deep/a/b/c"
helper_root_physical="$(cd -P "$helper_root" && pwd -P)"
physical_temp=0
[ "$helper_root_physical" = "$helper_root" ] && physical_temp=1
# A root-ancestor probe: the nearest existing ancestor of this path IS "/", which is the
# one case where `pwd -P` spells "/" and the reattached remainder spells "/...". Read
# only -- the path is never created.
root_ancestor_case="/sefi-installer-root-ancestor-probe-$$/nested/leaf"

harness_count=0
for helper_entry in \
  "install.sh|$ROOT/install.sh" \
  "install-codex.sh|$ROOT/install-codex.sh" \
  "install-opencode.sh|$OPENCODE_INSTALL"; do
  helper_name="${helper_entry%%|*}"
  helper_script="${helper_entry#*|}"
  harness="$tmp/helpers-$helper_name.sh"
  extract_installer_function "$helper_script" sefi_normalize_path > "$harness"
  extract_installer_function "$helper_script" sefi_canonical_path >> "$harness"
  extract_installer_function "$helper_script" sefi_inside_or_equal >> "$harness"
  if grep -q '^sefi_normalize_path() {' "$harness" \
    && grep -q '^sefi_canonical_path() {' "$harness" \
    && grep -q '^sefi_inside_or_equal() {' "$harness" \
    && bash -n "$harness"; then
    ok "$helper_name ships both path helpers and the containment predicate in a loadable form"
  else
    bad "$helper_name ships both path helpers and the containment predicate in a loadable form"
    continue
  fi
  harness_count=$((harness_count + 1))

  # The nearest existing ancestor is the filesystem root, so a raw concatenation of the
  # two halves printed "//nested/leaf" -- a spelling no destination could ever match,
  # which made refuse_* reject a legitimate path.
  check_helper_prints "$helper_name canonicalizes a root-ancestor path byte-exactly" \
    "$harness" sefi_canonical_path "$root_ancestor_case" "$root_ancestor_case"

  if [ "$physical_temp" -eq 1 ]; then
    # An existing subdir with no symlink anywhere in the chain: this is the comparison
    # refuse_* relies on before it will trust a spelled DEST.
    check_helper_prints "$helper_name canonicalizes an existing subdir byte-exactly" \
      "$harness" sefi_canonical_path "$helper_root/deep/a/b/c" "$helper_root/deep/a/b/c"
    # A trailing slash must not survive into the comparison, and a non-existent leaf
    # under an existing parent must reattach without a doubled separator.
    check_helper_prints "$helper_name strips a trailing slash before comparing" \
      "$harness" sefi_canonical_path "$helper_root/deep/a/b/c/" "$helper_root/deep/a/b/c"
    check_helper_prints "$helper_name canonicalizes a missing leaf under an existing parent" \
      "$harness" sefi_canonical_path "$helper_root/deep/not-created-yet/leaf" \
      "$helper_root/deep/not-created-yet/leaf"
  else
    printf 'PENDING: %s byte-equality checks need a physical, case-preserving fixture temp (got %s)\n' \
      "$helper_name" "$helper_root_physical"
  fi

  # Input no POSIX layer can interpret is refused outright, not folded into one literal
  # relative component under $PWD. Every installer runs cygpath -u at its entry point,
  # so these are exactly the values that escaped normalization; install-codex.sh never
  # cygpaths CODEX_HOME at all, so the end-to-end check below is its own seam.
  check_helper_refuses "$helper_name rejects a backslash path" \
    "$harness" sefi_normalize_path 'sub\dir'
  check_helper_refuses "$helper_name rejects a drive-letter path" \
    "$harness" sefi_normalize_path 'C:\Users\you\.config\opencode'
  check_helper_refuses "$helper_name rejects a forward-slash drive-letter path" \
    "$harness" sefi_normalize_path 'C:/Users/you/.config/opencode'
  check_helper_refuses "$helper_name rejects an MSYS-style drive-letter path" \
    "$harness" sefi_normalize_path '/C:/Users/you'
  check_helper_refuses "$helper_name propagates a backslash refusal through the canonical helper" \
    "$harness" sefi_canonical_path 'sub\dir'
  check_helper_refuses "$helper_name propagates a drive-letter refusal through the canonical helper" \
    "$harness" sefi_canonical_path 'C:\Users\you\.config\opencode'
  # Empty input is unreachable from the installers -- every entry point substitutes a
  # default for an unset or empty variable -- but normalized bare it resolved to $PWD,
  # which would have installed into whatever directory the user happened to be standing
  # in. Pinned here so that cannot come back silently.
  check_helper_refuses "$helper_name rejects empty input instead of resolving to the working directory" \
    "$harness" sefi_normalize_path ''
  # A legitimate relative path with delimiter characters is still valid input and must
  # still absolutize, so the refusals above cannot be satisfied by a blanket "anything
  # unusual is an error" rule.
  check_helper_prints "$helper_name still absolutizes a legitimate relative path" \
    "$harness" sefi_normalize_path './a&b#c' "$fixture_pwd/a&b#c"

  # Multiple leading slashes before a drive letter are the same MSYS-style path as a
  # single one. Stripping only the first left the separator in front of the drive
  # letter, where the case could not match it, so //C:/ and ///C:/ folded in as
  # relative components and were installed as directory names.
  check_helper_refuses "$helper_name rejects a double-slash drive-letter path" \
    "$harness" sefi_normalize_path '//C:/Users/you'
  check_helper_refuses "$helper_name rejects a triple-slash drive-letter path" \
    "$harness" sefi_normalize_path '///C:/Users/you'
  check_helper_refuses "$helper_name propagates a double-slash drive-letter refusal through the canonical helper" \
    "$harness" sefi_canonical_path '//C:/Users/you'
  # A UNC-style double slash with no drive letter is a legitimate POSIX path and must
  # keep normalizing, so the refusals above cannot be satisfied by rejecting "//".
  check_helper_prints "$helper_name still normalizes a UNC-style double-slash path" \
    "$harness" sefi_normalize_path '//server/share' '/server/share'

  # sefi_inside_or_equal is what refuse_* trusts once a physical path differs from the
  # spelled one. It is a pure string predicate, so these need no physical fixture and
  # are never PENDING.
  check_helper_status "$helper_name containment accepts an exact match" \
    "$harness" sefi_inside_or_equal 0 '/home/u/.codex' '/home/u/.codex'
  check_helper_status "$helper_name containment accepts a child" \
    "$harness" sefi_inside_or_equal 0 '/home/u/.codex/agents' '/home/u/.codex'
  # The sibling-prefix trap: the candidate shares every character of the root but is
  # not inside it. A bare prefix test accepts this, which would wave a neighbour
  # directory through as "inside" the install root.
  check_helper_status "$helper_name containment rejects a sibling sharing the root prefix" \
    "$harness" sefi_inside_or_equal 1 '/home/u/.codexevil' '/home/u/.codex'
  check_helper_status "$helper_name containment rejects a hyphen-suffixed sibling" \
    "$harness" sefi_inside_or_equal 1 '/home/u/.codex-evil/agents' '/home/u/.codex'
  check_helper_status "$helper_name containment rejects an unrelated subtree" \
    "$harness" sefi_inside_or_equal 1 '/home/u/.other/agents' '/home/u/.codex'
  check_helper_status "$helper_name containment rejects a prefix of the root" \
    "$harness" sefi_inside_or_equal 1 '/home/u' '/home/u/.codex'
  # A root of "/" is the filesystem itself; only itself is inside it.
  check_helper_status "$helper_name containment accepts the filesystem root as itself" \
    "$harness" sefi_inside_or_equal 0 '/' '/'
  check_helper_status "$helper_name containment rejects anything under a bare filesystem root" \
    "$harness" sefi_inside_or_equal 1 '/home/u' '/'
  # Glob characters in a root must be compared literally, never expanded.
  check_helper_status "$helper_name containment compares glob characters literally" \
    "$harness" sefi_inside_or_equal 0 '/home/u/*/agents' '/home/u/*'
  check_helper_status "$helper_name containment rejects a glob-shaped sibling" \
    "$harness" sefi_inside_or_equal 1 '/home/u/*evil' '/home/u/*'
  check_helper_status "$helper_name containment rejects an empty candidate" \
    "$harness" sefi_inside_or_equal 1 '' '/home/u/.codex'
  check_helper_status "$helper_name containment rejects an empty root" \
    "$harness" sefi_inside_or_equal 1 '/home/u/.codex' ''
done

# The three installers carry these helpers by copy, so a fix applied to one and missed in
# the others is precisely the drift the per-installer assertions above would not catch.
if [ "$harness_count" -eq 3 ] \
  && [ "$(sha256sum "$tmp"/helpers-*.sh | awk '{print $1}' | sort -u | wc -l)" -eq 1 ]; then
  ok "all three installers ship byte-identical path helpers"
else
  bad "all three installers ship byte-identical path helpers"
fi

# End-to-end for the same refusal, through the one installer that never cygpath-converts
# its destination. A Windows-style CODEX_HOME therefore reaches the normalizer untouched.
# It runs from a scratch directory inside the fixture temp: a regression that "helpfully"
# accepted the value would create the literal directory there, where the cleanup trap
# removes it, instead of anywhere near a real profile.
codex_win_probe="$tmp/codex-windows-path-probe"
mkdir -p "$codex_win_probe"
expect_failure "Codex refuses a drive-letter CODEX_HOME" \
  env PATH="$codex_bin:$PATH" CODEX_HOME='C:\Users\you\.codex' CODEX_TEST_SOURCE="$CORE" \
  CODEX_TEST_MARKETPLACE_ROOT="$ROOT" CODEX_TEST_MARKETPLACE_SOURCE="$ROOT" \
  bash -c 'cd "$1" || exit 1; shift; exec bash "$@"' _ "$codex_win_probe" "$ROOT/install-codex.sh" --candidate-marketplace "$ROOT"
# The refusal has to come from the normalizer, not from an incidental failure earlier in
# the run. A filesystem that cannot represent a backslash inside a directory name rejects
# the same value for an unrelated reason, so the message is only demanded where the name
# is representable. Probe a separate fixture so a regression that created the installer
# destination cannot turn a supported filesystem into a false capability skip.
codex_win_probe_capability="$(mktemp -d "$tmp/codex-windows-path-capability.XXXXXX")"
if mkdir "$codex_win_probe_capability/C:\Users\you\.codex" 2>/dev/null; then
  rm -rf "$codex_win_probe_capability"
  if grep -qF 'refusing CODEX_HOME that is not a POSIX path' \
    "$tmp/Codex refuses a drive-letter CODEX_HOME.out"; then
    ok "Codex names the non-POSIX-path refusal rather than failing later"
  else
    bad "Codex names the non-POSIX-path refusal rather than failing later"
  fi
  if [ ! -e "$codex_win_probe/C:\Users\you\.codex/AGENTS.md" ]; then
    ok "Codex wrote no bootstrap block through a drive-letter CODEX_HOME"
  else
    bad "Codex wrote no bootstrap block through a drive-letter CODEX_HOME"
  fi
else
  printf 'PENDING: Codex non-POSIX-path refusal message needs a filesystem that can spell a drive letter as a directory name\n'
fi

# Hermes's CLI is simulated only for the installer seam. It copies the requested candidate
# bytes, and can deliberately corrupt one fetched skill to exercise the integrity check.
fake_bin="$tmp/bin"
hermes_config="$tmp/hermes/config"
mkdir -p "$fake_bin" "$hermes_config"
cat >"$fake_bin/hermes" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  config)
    [ "${2:-}" = path ] || exit 64
    printf '%s\n' "$HERMES_TEST_CONFIG/config.toml"
    ;;
  skills)
    case "${2:-}" in
      install)
        name="$(basename "${3:-}")"
        target="$(dirname "$HERMES_TEST_CONFIG/config.toml")/skills/$name"
        mkdir -p "$target"
        cp -R "$HERMES_TEST_SOURCE/skills/$name/." "$target/"
        if [ "${HERMES_TEST_MISMATCH:-}" = "$name" ]; then printf '\ncorrupt\n' >>"$target/SKILL.md"; fi
        # Runtime-copy symlink simulation: one fetched file is replaced by a link to a
        # sibling the installer did not create. A tree carrying a link must be refused
        # as untrusted, never resolved and compared through.
        if [ "${HERMES_TEST_SYMLINK_SKILL:-}" = "$name" ]; then
          printf 'unrelated runtime-copy victim\n' >"$target/unrelated-victim.txt"
          rm -f "$target/SKILL.md"
          ln -s './unrelated-victim.txt' "$target/SKILL.md"
        fi
        ;;
      list)
        vbar_sp=$(printf '\342\224\202 ')
        sp_vbar=$(printf ' \342\224\202')
        printf '%sName%s Source%s\n' "$vbar_sp" "$sp_vbar" "$sp_vbar"
        for skill in "$(dirname "$HERMES_TEST_CONFIG/config.toml")"/skills/*; do
          [ -d "$skill" ] || continue
          printf '%s%s%s local%s\n' "$vbar_sp" "$(basename "$skill")" "$sp_vbar" "$sp_vbar"
        done
        ;;
      *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$fake_bin/hermes"
hermes_env=(env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_config" HERMES_TEST_SOURCE="$CORE")
runtime="$(dirname "$hermes_config/config.toml")/sefi-core"

expect_success "Hermes fresh install creates the managed runtime" "${hermes_env[@]}" bash "$HERMES_INSTALL"
# A launcher symlink must not redirect the readable package helper lookup to a writable
# sibling directory.
attacker_dir="$tmp/hermes-symlink-attacker"
mkdir -p "$attacker_dir"
ln -s "$HERMES_INSTALL" "$attacker_dir/install-hermes.sh"
if [ -L "$attacker_dir/install-hermes.sh" ]; then
  cat > "$attacker_dir/package-manifest.sh" <<'ATTACKER_HELPER'
#!/usr/bin/env bash
printf 'UNTRUSTED_HELPER_EXECUTED\n' > "${HERMES_ATTACK_MARKER:?}"
exit 99
ATTACKER_HELPER
  chmod 0644 "$attacker_dir/package-manifest.sh"
  attack_marker="$tmp/untrusted-helper-executed"
  expect_success "Hermes symlink entrypoint binds its package helper to the trusted installer" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_config" HERMES_TEST_SOURCE="$CORE" HERMES_ATTACK_MARKER="$attack_marker" bash "$attacker_dir/install-hermes.sh"
  if [ ! -e "$attack_marker" ]; then
    ok "Hermes symlink entrypoint never executes an adjacent untrusted helper"
  else
    bad "Hermes symlink entrypoint executed an adjacent helper"
  fi
  ln -s "$attacker_dir/missing-installer.sh" "$attacker_dir/broken-installer.sh"
  expect_failure "Hermes rejects a broken installer symlink before helper lookup" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_config" HERMES_TEST_SOURCE="$CORE" HERMES_ATTACK_MARKER="$attack_marker" bash "$attacker_dir/broken-installer.sh"
  ln -s "$attacker_dir/loop-b.sh" "$attacker_dir/loop-a.sh"
  ln -s "$attacker_dir/loop-a.sh" "$attacker_dir/loop-b.sh"
  expect_failure "Hermes bounds an installer symlink loop before helper lookup" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_config" HERMES_TEST_SOURCE="$CORE" HERMES_ATTACK_MARKER="$attack_marker" bash "$attacker_dir/loop-a.sh"
  if [ ! -e "$attack_marker" ]; then
    ok "Hermes broken and looping entrypoints never execute an adjacent helper"
  else
    bad "Hermes broken or looping entrypoints executed an adjacent helper"
  fi
else
  printf 'PENDING: Hermes symlink-entrypoint checks require a physical symlink\n'
fi
if [ -f "$runtime/.sefi-agents-manifest.json" ] \
  && [ -f "$runtime/agents/systems-auditor.md" ] \
  && [ -f "$runtime/skills/systems-audit/references/report-contract.md" ] \
  && [ -f "$runtime/scripts/ci/validate-audit-report.sh" ] \
  && [ -f "$runtime/config/model-map.yml" ] \
  && [ -f "$runtime/commands/audit.md" ] \
  && [ -f "$runtime/templates/audits/.gitkeep" ]; then
  ok "Hermes runtime contains canonical audit dependencies"
else
  bad "Hermes runtime contains canonical audit dependencies"
fi
if python - "$CORE" "$runtime" "$BASE_HEAD" "$BASE_TREE" "$CANDIDATE_TREE" "$CANDIDATE_PATCH_SHA256" "$EMPTY_PATCH_SHA256" "$CANDIDATE_IDENTITY" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

source = Path(sys.argv[1])
runtime = Path(sys.argv[2])
base_head, base_tree, candidate_tree, candidate_patch, empty_patch, identity = sys.argv[3:]
manifest = json.loads((runtime / ".sefi-agents-manifest.json").read_text(encoding="utf-8"))
if manifest.get("source_commit") != base_head:
    raise SystemExit("manifest source_commit does not equal base HEAD")
if len(candidate_patch) != 64 or set(candidate_patch) - set("0123456789abcdef"):
    raise SystemExit("candidate patch SHA-256 is invalid")
if identity == "clean-committed":
    if candidate_tree != base_tree or candidate_patch != empty_patch:
        raise SystemExit("clean committed candidate has staged identity data")
elif identity == "staged":
    if candidate_tree == base_tree or candidate_patch == empty_patch:
        raise SystemExit("staged candidate has no staged identity data")
else:
    raise SystemExit(f"unknown candidate identity mode: {identity}")
def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
source_hashes = {
    path.relative_to(source).as_posix(): digest(path)
    for path in sorted(source.rglob("*")) if path.is_file() and not path.is_symlink()
}
if manifest.get("managed_files") != source_hashes:
    raise SystemExit("manifest hashes do not equal candidate source content")
for relative, expected in source_hashes.items():
    installed = runtime / relative
    if not installed.is_file() or digest(installed) != expected:
        raise SystemExit(f"installed managed content mismatch: {relative}")
candidate_content = hashlib.sha256(
    "".join(f"{relative}\0{digest}\n" for relative, digest in sorted(source_hashes.items())).encode()
).hexdigest()
print(f"identity={identity} base={base_head} base-tree={base_tree} candidate-tree={candidate_tree} candidate-patch-sha256={candidate_patch} candidate-content-sha256={candidate_content} files={len(source_hashes)}")
PY
then
  ok "Hermes records base revision and every candidate managed-file hash"
else
  bad "Hermes records base revision and every candidate managed-file hash"
fi
if python - "$runtime" "$(dirname "$hermes_config/config.toml")/skills/systems-audit/references/report-contract.md" <<'PY'
import re
import sys
from pathlib import Path

runtime = Path(sys.argv[1])
contract = Path(sys.argv[2]).read_text(encoding="utf-8")
expected = (runtime / "scripts" / "ci" / "validate-audit-report.sh").resolve()
matches = re.findall(r"(?:[A-Za-z]:)?[^`\s)]*/scripts/ci/validate-audit-report\.sh", contract)
if not any(Path(value).resolve().samefile(expected) for value in matches if Path(value).is_file()):
    raise SystemExit("installed report contract does not resolve to the runtime validator")
PY
then
  ok "Hermes installed audit skill resolves its managed runtime"
else
  bad "Hermes installed audit skill resolves its managed runtime"
fi

expect_success "Hermes repeat install is idempotent" "${hermes_env[@]}" bash "$HERMES_INSTALL"

hermes_symlink_core="$tmp/hermes-runtime-symlink-source/sefi-core"
hermes_symlink_config="$tmp/hermes-runtime-symlink/config"
hermes_symlink_runtime="$(dirname "$hermes_symlink_config/config.toml")/sefi-core"
mkdir -p "$(dirname "$hermes_symlink_core")" "$hermes_symlink_config"
cp -R "$CORE" "$hermes_symlink_core"
rm -f "$hermes_symlink_core/scripts/ci/format-audit-findings.sh"
expect_success "Hermes prepares a runtime missing one future managed file" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_symlink_config" HERMES_TEST_SOURCE="$hermes_symlink_core" bash "$hermes_symlink_core/scripts/install-hermes.sh"
mkdir -p "$hermes_symlink_runtime/user-content"
printf 'unrelated runtime content\n' > "$hermes_symlink_runtime/user-content/keep.txt"
if ln -s '../../user-content/keep.txt' "$hermes_symlink_runtime/scripts/ci/format-audit-findings.sh" 2>/dev/null \
  && [ -L "$hermes_symlink_runtime/scripts/ci/format-audit-findings.sh" ]; then
  expect_failure "Hermes auto-update rejects a managed destination symlink" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_symlink_config" HERMES_TEST_SOURCE="$CORE" bash "$HERMES_INSTALL" --auto-update
  if grep -qxF 'unrelated runtime content' "$hermes_symlink_runtime/user-content/keep.txt"; then
    ok "Hermes destination symlink leaves unrelated runtime content unchanged"
  else
    bad "Hermes destination symlink leaves unrelated runtime content unchanged"
  fi
else
  printf 'PENDING: Hermes destination-symlink check requires a physical symlink\n'
fi

hermes_retired_symlink_core="$tmp/hermes-retired-symlink-source/sefi-core"
hermes_retired_symlink_config="$tmp/hermes-retired-symlink/config"
hermes_retired_symlink_runtime="$(dirname "$hermes_retired_symlink_config/config.toml")/sefi-core"
mkdir -p "$(dirname "$hermes_retired_symlink_core")" "$hermes_retired_symlink_config"
cp -R "$CORE" "$hermes_retired_symlink_core"
expect_success "Hermes prepares a runtime with a managed file for retirement" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_retired_symlink_config" HERMES_TEST_SOURCE="$hermes_retired_symlink_core" bash "$hermes_retired_symlink_core/scripts/install-hermes.sh"
rm -f "$hermes_retired_symlink_core/commands/audit.md" "$hermes_retired_symlink_runtime/commands/audit.md"
mkdir -p "$hermes_retired_symlink_runtime/user-content"
printf 'unrelated retired-path content\n' > "$hermes_retired_symlink_runtime/user-content/keep.txt"
if ln -s '../user-content/keep.txt' "$hermes_retired_symlink_runtime/commands/audit.md" 2>/dev/null \
  && [ -L "$hermes_retired_symlink_runtime/commands/audit.md" ]; then
  expect_failure "Hermes auto-update rejects a symlinked retired managed path" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_retired_symlink_config" HERMES_TEST_SOURCE="$hermes_retired_symlink_core" bash "$hermes_retired_symlink_core/scripts/install-hermes.sh" --auto-update
  if [ -L "$hermes_retired_symlink_runtime/commands/audit.md" ] \
    && grep -qxF 'unrelated retired-path content' "$hermes_retired_symlink_runtime/user-content/keep.txt"; then
    ok "Hermes retired managed symlink leaves unrelated runtime content unchanged"
  else
    bad "Hermes retired managed symlink leaves unrelated runtime content unchanged"
  fi
else
  printf 'PENDING: Hermes retired-path symlink check requires a physical symlink\n'
fi

# Behavioral replacements for the two greps on install-hermes.sh's installed_path
# symlink guard. Those greps passed on the comment alone once the guarded code was
# removed. The auto-update half of the guard is already covered behaviourally by the
# destination-symlink and retired-path-symlink cases above, which assert both the
# refusal and that the linked-to file is untouched. This adds the missing half: a
# runtime COPY that itself carries a symlink must be refused, never resolved through.
#
# Guarded by the same symlink-capability probe as the other symlink cases: where ln -s
# copies instead of linking, the fetch is a byte mismatch (still refused, but for the
# wrong reason) and the link assertion would be meaningless, so it is reported PENDING.
if [ "$symlinks_supported" -eq 1 ]; then
  hermes_copy_symlink_config="$tmp/hermes-copy-symlink/config"
  hermes_copy_symlink_runtime="$(dirname "$hermes_copy_symlink_config/config.toml")"
  mkdir -p "$hermes_copy_symlink_config"
  expect_failure "Hermes rejects a fetched runtime copy containing a symlink" \
    env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_copy_symlink_config" HERMES_TEST_SOURCE="$CORE" HERMES_TEST_SYMLINK_SKILL=systems-audit bash "$HERMES_INSTALL"
  if grep -q 'differs from the expected source' \
    "$tmp/Hermes rejects a fetched runtime copy containing a symlink.out"; then
    ok "Hermes names the runtime-copy integrity failure rather than reporting success"
  else
    bad "Hermes names the runtime-copy integrity failure rather than reporting success"
  fi
  # Refusal rolls the fetch back: with no pre-install backup, restore_skills removes
  # the fetched tree, so the tainted link must be gone rather than live -- and no
  # managed runtime may have been materialized from the tainted fetch. Either
  # survivor means the installer resolved through the link instead of refusing it.
  if [ ! -e "$hermes_copy_symlink_runtime/skills/systems-audit/SKILL.md" ] \
    && [ ! -e "$hermes_copy_symlink_runtime/sefi-core" ]; then
    ok "Hermes quarantines a fetched runtime-copy symlink instead of resolving through it"
  else
    bad "Hermes quarantines a fetched runtime-copy symlink instead of resolving through it"
  fi
else
  printf 'PENDING: Hermes runtime-copy symlink check requires a physical symlink\n'
fi

# The fetched-tree check above must reject a symlink before the installer copies a
# runtime. This separate fixture exercises the later seam: normal fetch validation
# completes, then only the runtime cp is wrapped to replace one copied file with a
# source-byte-identical in-runtime symlink. The post-copy verifier must reject the link
# directly and restore the live skill snapshot.
hermes_runtime_copy_bin="$tmp/hermes-runtime-copy-bin"
hermes_runtime_copy_config="$tmp/hermes-runtime-copy/config"
hermes_runtime_copy_root="$(dirname "$hermes_runtime_copy_config/config.toml")"
hermes_runtime_copy_runtime="$hermes_runtime_copy_root/sefi-core"
hermes_runtime_copy_relative="scripts/ci/validate-audit-report.sh"
hermes_runtime_copy_target="$hermes_runtime_copy_runtime/.runtime-copy-symlink-victim"
hermes_runtime_copy_live_skill="$hermes_runtime_copy_root/skills/systems-audit/SKILL.md"
mkdir -p "$hermes_runtime_copy_bin" "$(dirname "$hermes_runtime_copy_live_skill")" "$hermes_runtime_copy_config"
printf 'pre-install systems-audit sentinel\n' >"$hermes_runtime_copy_live_skill"
hermes_runtime_copy_live_before="$(sha256sum "$hermes_runtime_copy_live_skill" | awk '{print $1}')"
hermes_runtime_copy_source_before="$(sha256sum "$CORE/$hermes_runtime_copy_relative" | awk '{print $1}')"
cat >"$hermes_runtime_copy_bin/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/bin/cp "$@"
if [ "$#" -eq 3 ] && [ "$1" = "-R" ] \
  && [ "$2" = "$HERMES_RUNTIME_COPY_SOURCE/." ] \
  && [ "$3" = "$HERMES_RUNTIME_COPY_DEST/" ]; then
  source_path="$HERMES_RUNTIME_COPY_SOURCE/$HERMES_RUNTIME_COPY_RELATIVE"
  installed_path="$HERMES_RUNTIME_COPY_DEST/$HERMES_RUNTIME_COPY_RELATIVE"
  target_path="$HERMES_RUNTIME_COPY_DEST/.runtime-copy-symlink-victim"
  /bin/cp "$source_path" "$target_path"
  rm -f "$installed_path"
  ln -s "../../.runtime-copy-symlink-victim" "$installed_path"
fi
EOF
chmod +x "$hermes_runtime_copy_bin/cp"
expect_failure "Hermes rejects an in-runtime symlink after normal fetch validation" \
  env PATH="$hermes_runtime_copy_bin:$fake_bin:$PATH" \
  HERMES_TEST_CONFIG="$hermes_runtime_copy_config" HERMES_TEST_SOURCE="$CORE" \
  HERMES_RUNTIME_COPY_SOURCE="$CORE" HERMES_RUNTIME_COPY_DEST="$hermes_runtime_copy_runtime" \
  HERMES_RUNTIME_COPY_RELATIVE="$hermes_runtime_copy_relative" \
  bash "$HERMES_INSTALL"
if grep -qxF "installed runtime file is missing or symlinked: $hermes_runtime_copy_relative" \
  "$tmp/Hermes rejects an in-runtime symlink after normal fetch validation.out"; then
  ok "Hermes names the post-copy runtime symlink refusal exactly"
else
  bad "Hermes names the post-copy runtime symlink refusal exactly"
fi
hermes_runtime_copy_target_after="$(sha256sum "$hermes_runtime_copy_target" | awk '{print $1}')"
if [ "$hermes_runtime_copy_source_before" = "$hermes_runtime_copy_target_after" ]; then
  ok "Hermes runtime-copy symlink target retains source-identical bytes"
else
  bad "Hermes runtime-copy symlink target retains source-identical bytes"
fi
hermes_runtime_copy_live_after="$(sha256sum "$hermes_runtime_copy_live_skill" | awk '{print $1}')"
if [ "$hermes_runtime_copy_live_before" = "$hermes_runtime_copy_live_after" ]; then
  ok "Hermes post-copy refusal restores the pre-install skill sentinel"
else
  bad "Hermes post-copy refusal restores the pre-install skill sentinel"
fi

# A skill-only v0.9.4-style installation has no runtime; auto-update must add one.
safe_remove_under_tmp "$runtime"
expect_success "Hermes auto-update upgrades a skill-only installation" "${hermes_env[@]}" bash "$HERMES_INSTALL" --auto-update
if [ -f "$runtime/.sefi-agents-manifest.json" ]; then ok "Hermes auto-update detects and repairs missing runtime assets"; else bad "Hermes auto-update detects and repairs missing runtime assets"; fi

# A stale revision is safe to refresh; unrelated files beside managed content survive.
mkdir -p "$runtime/user-content"
printf 'preserve\n' >"$runtime/user-content/keep.txt"
sed -i 's/"source_commit": "[^"]*"/"source_commit": "mismatched-source"/' "$runtime/.sefi-agents-manifest.json"
expect_success "Hermes auto-update refreshes a source-revision mismatch" "${hermes_env[@]}" bash "$HERMES_INSTALL" --auto-update
if [ -f "$runtime/user-content/keep.txt" ]; then ok "Hermes preserves unrelated runtime content"; else bad "Hermes preserves unrelated runtime content"; fi

# A stale runtime must remove a formerly managed file that no longer exists in the source,
# while retaining never-managed user content beside it.
trimmed_core="$tmp/trimmed/sefi-core"
mkdir -p "$(dirname "$trimmed_core")"
cp -R "$CORE" "$trimmed_core"
rm -f "$trimmed_core/commands/audit.md"
printf 'preserve-after-prune\n' >"$runtime/user-content/keep-after-prune.txt"
expect_success "Hermes auto-update removes source-deleted managed runtime files" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$hermes_config" HERMES_TEST_SOURCE="$trimmed_core" bash "$trimmed_core/scripts/install-hermes.sh" --auto-update
if [ ! -e "$runtime/commands/audit.md" ] \
  && [ -f "$runtime/user-content/keep-after-prune.txt" ]; then
  ok "Hermes prunes only source-deleted managed files"
else
  bad "Hermes prunes only source-deleted managed files"
fi

# A managed-file edit is drift and must stop before any silent overwrite.
printf 'user change\n' >>"$runtime/scripts/sefi-runtime.py"
expect_failure "Hermes auto-update refuses modified managed runtime content" "${hermes_env[@]}" bash "$HERMES_INSTALL" --auto-update

# A fetched mismatch must restore the exact prior live skill, not merely return failure.
crlf_core="$tmp/hermes-crlf-checkout/sefi-core"
mkdir -p "$(dirname "$crlf_core")"
cp -R "$CORE" "$crlf_core"
python - "$crlf_core/skills" <<'PY'
import sys
from pathlib import Path

for path in Path(sys.argv[1]).rglob("*"):
    if path.is_file() and path.suffix == ".md":
        content = path.read_bytes().replace(b"\r\n", b"\n")
        path.write_bytes(content.replace(b"\n", b"\r\n"))
PY
crlf_config="$tmp/hermes-crlf/config"
mkdir -p "$crlf_config"
expect_success "Hermes accepts LF fetched skill content from a CRLF checkout source" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$crlf_config" HERMES_TEST_SOURCE="$CORE" bash "$crlf_core/scripts/install-hermes.sh"
crlf_before_mismatch="$(sha256sum "$crlf_config/skills/systems-audit/SKILL.md" | awk '{print $1}')"
expect_failure "Hermes rejects corrupt fetched skill content against a CRLF checkout source" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$crlf_config" HERMES_TEST_SOURCE="$CORE" HERMES_TEST_MISMATCH=systems-audit bash "$crlf_core/scripts/install-hermes.sh"
crlf_after_mismatch="$(sha256sum "$crlf_config/skills/systems-audit/SKILL.md" | awk '{print $1}')"
if [ "$crlf_before_mismatch" = "$crlf_after_mismatch" ]; then
  ok "Hermes CRLF source mismatch restores exact prior live skill bytes"
else
  bad "Hermes CRLF source mismatch restores exact prior live skill bytes"
fi

bad_config="$tmp/hermes-mismatch/config"
mkdir -p "$bad_config"
expect_success "Hermes prepares a live skill for rollback verification" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$bad_config" HERMES_TEST_SOURCE="$CORE" bash "$HERMES_INSTALL"
before_mismatch="$(sha256sum "$bad_config/skills/systems-audit/SKILL.md" | awk '{print $1}')"
expect_failure "Hermes rejects fetched skill content that differs from expected source" \
  env PATH="$fake_bin:$PATH" HERMES_TEST_CONFIG="$bad_config" HERMES_TEST_SOURCE="$CORE" HERMES_TEST_MISMATCH=systems-audit bash "$HERMES_INSTALL"
after_mismatch="$(sha256sum "$bad_config/skills/systems-audit/SKILL.md" | awk '{print $1}')"
if [ "$before_mismatch" = "$after_mismatch" ]; then
  ok "Hermes mismatch restores exact prior live skill bytes"
else
  bad "Hermes mismatch restores exact prior live skill bytes"
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo 'test-systems-audit-installers: PASS'
