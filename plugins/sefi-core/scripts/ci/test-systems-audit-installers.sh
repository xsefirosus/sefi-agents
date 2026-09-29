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

safe_remove_under_tmp() {
  # Resolve each recursive-delete target before acting. These fixtures run on Windows too,
  # where an unintended drive-root or profile-root target would be unrecoverable.
  local target="$1" parent resolved
  parent="$(dirname "$target")"
  resolved="$(cd -P "$parent" && pwd -P)/$(basename "$target")"
  case "$resolved" in
    "$tmp_resolved"|"$tmp_resolved"/*) rm -rf -- "$resolved" ;;
    *) printf 'REFUSED: cleanup target escapes fixture temp directory: %s\n' "$resolved" >&2; return 1 ;;
  esac
}

cleanup() { safe_remove_under_tmp "$tmp" || :; }
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
