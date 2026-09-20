#!/usr/bin/env bash
# test-design-council-routing.sh -- offline contract checks for v0.9 design routing and packaging.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
ROUTING="$CORE/skills/sefi-orchestration/references/routing-table.md"
ORCHESTRATION="$CORE/skills/sefi-orchestration/SKILL.md"
HERMES_INSTALLER="$CORE/scripts/install-hermes.sh"
OPENCODE_INSTALLER="$CORE/scripts/install-opencode.sh"
FALLBACK_INSTALLER="$ROOT/install.sh"
CODEX_BOOTSTRAP="$ROOT/install-codex.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }
has_all() {
  local file="$1" label="$2"
  shift 2
  local needle
  for needle in "$@"; do
    if ! grep -Fq -- "$needle" "$file"; then
      bad "$label missing: $needle"
      return
    fi
  done
  ok "$label"
}

has_all "$ROUTING" 'generic-web platform exclusions' \
  'Generic web design' 'must not load swiftui-design or expo-native-design'
has_all "$ROUTING" 'selective platform routes' \
  'SwiftUI or native Apple work loads swiftui-design only' \
  'Expo or React Native work loads expo-native-design only'
has_all "$ROUTING" 'nontrivial motion dispatch' \
  'motion-complexity: nontrivial' 'motion-designer' \
  'explicitly involves animation'
has_all "$ORCHESTRATION" 'design-council sequence' \
  'UI/UX Designer -> conditional platform and' 'style skills -> Motion Designer when motion is nontrivial' \
  'Motion Designer when motion is nontrivial' 'UI/UX and Motion audits' 'QA Engineer'
has_all "$HERMES_INSTALLER" 'Hermes installer lists every v0.9 skill' \
  'motion-design' 'swiftui-design' 'expo-native-design' 'design-style-profiles'
has_all "$FALLBACK_INSTALLER" 'Claude fallback packages canonical agent and skill trees' \
  'for d in agents skills commands scripts; do'
has_all "$OPENCODE_INSTALLER" 'OpenCode packages every canonical agent and skill' \
  'for src in "$AGENTS_SRC"/*.md; do' \
  'for src_dir in "$SKILLS_SRC" "$COMMANDS_SRC" "$SCRIPTS_SRC"; do'
has_all "$CODEX_BOOTSTRAP" 'Codex bootstrap derives profiles from canonical agents' \
  'for source_agent in "$CORE"/agents/*.md; do'
has_all "$CORE/.claude-plugin/plugin.json" 'Claude package exposes the canonical skill tree' \
  '"skills": ["./skills/"]'
has_all "$CORE/.codex-plugin/plugin.json" 'Codex package exposes the canonical skill tree' \
  '"skills": "./skills/"'

for adapter in claude-code codex opencode hermes; do
  has_all "$ROOT/adapters/manifests/$adapter.yml" "$adapter adapter manifest remains shipped" \
    'schema: sefi-adapter/v1' "id: $adapter" 'verification: verified' 'support: shipped'
done

agent_count="$(find "$CORE/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
skill_count="$(find "$CORE/skills" -name SKILL.md | wc -l | tr -d ' ')"
if [ "$agent_count" = '16' ] && [ "$skill_count" = '19' ]; then
  ok 'v0.9 package source contains 16 agents and 19 skills'
else
  bad "v0.9 package source expected 16 agents and 19 skills, got $agent_count agents and $skill_count skills"
fi

if [ "$fail" -ne 0 ]; then
  printf 'test-design-council-routing: %s failed, %s passed\n' "$fail" "$pass"
  exit 1
fi
printf 'test-design-council-routing: OK (%s passed)\n' "$pass"
