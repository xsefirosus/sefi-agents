#!/usr/bin/env bash
# Offline regression checks for the v0.8 install and project-onboarding contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
BASH_EXEC="${BASH:-$(command -v bash)}"
failures=0

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; failures=$((failures + 1)); }

contains() {
  # contains <file> <literal> <description>
  if grep -Fq "$2" "$1"; then ok "$3"; else bad "$3"; fi
}

absent() {
  # absent <file> <literal> <description>
  if grep -Fq "$2" "$1"; then bad "$3"; else ok "$3"; fi
}

onboarding_message() {
  # onboarding_message <output-file> <harness>
  contains "$1" "installation succeeded" "$2 reports successful installation"
  contains "$1" "/sefi:init" "$2 tells users to initialize each project"
  contains "$1" "project root" "$2 identifies the init location"
  contains "$1" "auto-init is unsafe" "$2 explains why install cannot auto-initialize"
  contains "$1" "cross-project memory" "$2 describes the optional memory mirror"
  contains "$1" "off by default" "$2 states the safe memory default"
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "=== onboarding contract prose ==="
contains "$CORE/commands/init.md" "cross-project memory" "/sefi:init offers the memory choice"
contains "$CORE/commands/init.md" "non-interactive" "/sefi:init specifies a non-interactive choice"
contains "$CORE/commands/init.md" "cross_project_enabled: false" "/sefi:init chooses a disabled mirror when unattended"
contains "$CORE/commands/init.md" "memory/" "/sefi:init keeps runtime memory local to the project"
contains "$CORE/commands/init.md" "audits/" "/sefi:init creates and ignores the local audits/ directory"
contains "$CORE/commands/init.md" "/sefi:audit <scope>" "/sefi:init names the on-demand audit command"
contains "$CORE/commands/init.md" "on demand" "/sefi:init states that audits run on demand"
contains "$CORE/commands/init.md" "ignored-local report" "/sefi:init keeps audit reports local"
contains "$ROOT/adapters/OPENCODE.md" "opencode/muse-spark-1.3-contributor-free" "OpenCode scheduled examples use the contributor-free model"
absent "$ROOT/adapters/OPENCODE.md" "paid-model preflight" "OpenCode free workflow docs do not attach a paid-model preflight"

echo "=== offline installer completion messages ==="
CLAUDE_HOME="$TMP/claude-home"
mkdir -p "$CLAUDE_HOME/.claude/agents"
printf '%s\n' '# user-owned knowledge manager' > "$CLAUDE_HOME/.claude/agents/knowledge-manager.md"
if HOME="$CLAUDE_HOME" "$BASH_EXEC" "$ROOT/install.sh" --target claude --copy --force >"$TMP/claude.out" 2>&1; then
  onboarding_message "$TMP/claude.out" "Claude Code"
else
  bad "Claude Code fallback install completes offline"
fi
if grep -Fqx '# user-owned knowledge manager' "$CLAUDE_HOME/.claude/agents/knowledge-manager.md"; then
  ok "Claude install preserves a user-owned knowledge-manager"
else
  bad "Claude install preserves a user-owned knowledge-manager"
fi

OPENCODE_HOME="$TMP/opencode-home"
if OPENCODE_HOME="$OPENCODE_HOME" "$BASH_EXEC" "$CORE/scripts/install-opencode.sh" >"$TMP/opencode.out" 2>&1; then
  onboarding_message "$TMP/opencode.out" "OpenCode"
else
  bad "OpenCode install completes offline"
fi

HERMES_BIN="$TMP/hermes-bin"
HERMES_STATE="$TMP/hermes-installed"
mkdir -p "$HERMES_BIN"
cat > "$HERMES_BIN/hermes" <<'HERMES'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'skills install')
    printf '%s\n' "${3##*/}" >> "$HERMES_TEST_STATE"
    ;;
  'skills list')
    vbar_sp=$(printf '\342\224\202 ')
    sp_vbar=$(printf ' \342\224\202')
    printf '%sName%s Status%s\n' "$vbar_sp" "$sp_vbar" "$sp_vbar"
    sort -u "$HERMES_TEST_STATE" | while IFS= read -r name; do
      printf '%s%s%s enabled%s\n' "$vbar_sp" "$name" "$sp_vbar" "$sp_vbar"
    done
    ;;
  'config path')
    printf '%s\n' "${HERMES_TEST_HOME}/config.yml"
    ;;
  *)
    printf 'unexpected fake hermes invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
HERMES
chmod +x "$HERMES_BIN/hermes"
: > "$HERMES_STATE"
if PATH="$HERMES_BIN:$PATH" HERMES_TEST_STATE="$HERMES_STATE" HERMES_TEST_HOME="$TMP/hermes-home" \
  "$BASH_EXEC" "$CORE/scripts/install-hermes.sh" >"$TMP/hermes.out" 2>&1; then
  onboarding_message "$TMP/hermes.out" "Hermes"
else
  bad "Hermes install completes against the offline CLI fixture"
fi

CODEX_BIN="$TMP/codex-bin"
CODEX_HOME="$TMP/codex-home"
mkdir -p "$CODEX_BIN" "$CODEX_HOME"
cat > "$CODEX_BIN/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin marketplace list --json')
    printf '%s\n' '{"marketplaces":[]}'
    ;;
  'plugin marketplace add xsefirosus/sefi-agents'|'plugin marketplace upgrade sefi-agents')
    ;;
  'plugin add sefi-core@sefi-agents')
    mkdir -p "$CODEX_HOME/agents"
    for source_agent in "$ONBOARDING_CORE"/agents/*.md; do
      [ -f "$source_agent" ] || continue
      name="$(sed -n 's/^name:[[:space:]]*\([a-z0-9-]*\).*/\1/p' "$source_agent" | head -1)"
      cat > "$CODEX_HOME/agents/$name.toml" <<PROFILE
name = "$name"
developer_instructions = "fixture"
PROFILE
    done
    ;;
  *)
    printf 'unexpected fake codex invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
CODEX
chmod +x "$CODEX_BIN/codex"
if PATH="$CODEX_BIN:$PATH" CODEX_HOME="$CODEX_HOME" ONBOARDING_CORE="$CORE" \
  "$BASH_EXEC" "$ROOT/install-codex.sh" >"$TMP/codex.out" 2>&1; then
  onboarding_message "$TMP/codex.out" "Codex"
else
  bad "Codex bootstrap completes against the offline CLI fixture"
fi

echo "=== legacy knowledge-manager migration ==="
# A release that removes knowledge-manager.md must remove only prior managed copies. Make
# a compact throwaway core tree without that file so this can be verified without mutating
# the shared worktree the test itself is running from.
MIGRATION_CORE="$TMP/migration-core"
cp -R "$CORE" "$MIGRATION_CORE"
rm -f "$MIGRATION_CORE/agents/knowledge-manager.md"

managed_open="$TMP/managed-opencode"
mkdir -p "$managed_open/agents"
printf '%s\n' '---' 'managed-by: sefi-agents' '---' 'legacy managed profile' > "$managed_open/agents/knowledge-manager.md"
if OPENCODE_HOME="$managed_open" "$BASH_EXEC" "$MIGRATION_CORE/scripts/install-opencode.sh" --force >"$TMP/managed-opencode.out" 2>&1 \
  && [ ! -e "$managed_open/agents/knowledge-manager.md" ]; then
  ok "OpenCode migration removes a managed legacy knowledge-manager"
else
  bad "OpenCode migration removes a managed legacy knowledge-manager"
fi

user_open="$TMP/user-opencode"
mkdir -p "$user_open/agents"
printf '%s\n' '# user-owned knowledge manager' > "$user_open/agents/knowledge-manager.md"
if OPENCODE_HOME="$user_open" "$BASH_EXEC" "$MIGRATION_CORE/scripts/install-opencode.sh" --force >"$TMP/user-opencode.out" 2>&1 \
  && grep -Fqx '# user-owned knowledge manager' "$user_open/agents/knowledge-manager.md"; then
  ok "OpenCode migration preserves a user-owned knowledge-manager"
else
  bad "OpenCode migration preserves a user-owned knowledge-manager"
fi

if [ "$failures" -ne 0 ]; then
  printf 'test-onboarding-v08: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'test-onboarding-v08: PASS\n'
