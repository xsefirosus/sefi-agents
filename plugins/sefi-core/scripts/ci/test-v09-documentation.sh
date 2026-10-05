#!/usr/bin/env bash
# Offline documentation, provenance, and local-release checks for v0.9.x.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

fail=0
require_file() {
  if [ ! -f "$1" ]; then
    echo "FAIL: missing $1" >&2
    fail=1
  fi
}
require_text() {
  local file="$1" text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "FAIL: $file lacks: $text" >&2
    fail=1
  fi
}
require_once() {
  local file="$1" text="$2" count
  count="$(grep -Foc -- "$text" "$file" || true)"
  if [ "$count" -ne 1 ]; then
    echo "FAIL: $file expected one '$text', found $count" >&2
    fail=1
  fi
}
require_roster_files() {
  local roster="plugins/sefi-core/skills/sefi-orchestration/references/roster.md" entry rows=0 missing=0
  while IFS= read -r entry; do
    rows=$((rows + 1))
    if [ ! -f "plugins/sefi-core/agents/$entry.md" ]; then
      echo "FAIL: roster entry does not resolve to an agent file: $entry" >&2
      missing=$((missing + 1))
    fi
  done < <(sed -n 's/^|[[:space:]]*`\([^`]*\)`.*/\1/p' "$roster")
  if [ "$rows" -ne 17 ]; then
    echo "FAIL: roster expected 17 agent entries, found $rows" >&2
    fail=1
  fi
  if [ "$missing" -ne 0 ]; then
    fail=1
  fi
}

for file in docs/DESIGN-COUNCIL.md docs/MIGRATION-v0.9.0.md docs/RELEASE-v0.9.0.md; do
  require_file "$file"
done

for manifest in plugins/sefi-core/.claude-plugin/plugin.json plugins/sefi-core/.codex-plugin/plugin.json; do
  require_text "$manifest" '"version": "0.9.8"'
done
require_text .claude-plugin/marketplace.json '"version": "0.9.8"'
if [ "$(grep -Foc '"version": "0.9.8"' .claude-plugin/marketplace.json || true)" -ne 2 ]; then
  echo "FAIL: marketplace must carry v0.9.8 twice" >&2
  fail=1
fi

require_text README.md '17 AI agents'
require_text README.md 'The skills (20)'
require_text README.md 'Design Council'
require_text README.md 'Motion Designer'
require_text README.md 'docs/DESIGN-COUNCIL.md'
require_once README.md '/sefi:audit'
require_text plugins/sefi-core/README.md '/sefi:audit'
require_text Install.md 'v0.9.2'
require_text Install.md 'billing_mode'
require_text CHANGELOG.md '## [0.9.8] - 2026-10-05'
require_text CHANGELOG.md '## [0.9.7] - 2026-10-04'
require_text CHANGELOG.md '## [0.9.6] - 2026-10-03'
require_text CHANGELOG.md '## [0.9.5] - 2026-09-28'
require_text CHANGELOG.md '## [0.9.0] - 2026-09-20'
require_text docs/RELEASE-v0.9.0.md 'partially released'
require_file docs/RELEASE-v0.9.5.md
require_text docs/RELEASE-v0.9.5.md 'Systems Audit'
require_text docs/RELEASE-v0.9.5.md '# v0.9.5 Release Notes'
require_file docs/RELEASE-v0.9.6.md
require_text docs/RELEASE-v0.9.6.md 'billing_mode'
require_text docs/RELEASE-v0.9.6.md '# v0.9.6 Release Notes'
require_file docs/RELEASE-v0.9.7.md
require_text docs/RELEASE-v0.9.7.md 'billing_mode'
require_text docs/RELEASE-v0.9.7.md '# v0.9.7 Release Notes'
require_text plugins/sefi-core/skills/sefi-orchestration/references/harness-actions.md 'Claude project file (see coordinator profile)'
require_text plugins/sefi-core/skills/sefi-orchestration/references/harness-actions.md 'OpenCode project file (see coordinator profile)'
require_text plugins/sefi-core/skills/sefi-orchestration/references/harness-actions.md 'Codex project file (see coordinator profile)'
require_text plugins/sefi-core/agents/sefi-agents.md 'Files: CLAUDE.md (Claude); MEMORY.md (Hermes); AGENTS.md (OpenCode/Codex).'
require_text plugins/sefi-core/skills/sefi-orchestration/references/roster.md 'basename resolved to `agents/<basename>.md`'
require_text plugins/sefi-core/skills/release-tracking/SKILL.md '`opencode.json`'
require_text plugins/sefi-core/skills/release-tracking/SKILL.md 'Codex hidden `config.toml`'
require_text plugins/sefi-core/skills/release-tracking/SKILL.md '`install-hermes.sh`'
require_text plugins/sefi-core/skills/release-tracking/SKILL.md '`SKILLS=` list'
require_text plugins/sefi-core/skills/release-tracking/SKILL.md '`validate-adapters.sh` and `validate-config-wired.sh`'
require_text plugins/sefi-core/skills/security-review/references/security-checklist.md 'Downloads that lead to execution are pinned (checksum or version); a network stream'
require_text plugins/sefi-core/skills/security-review/references/security-checklist.md 'never feeds a shell directly.'
require_roster_files

for text in \
  'Product Context' \
  'Soft Premium' \
  'Minimal Editorial' \
  'Industrial Brutalist' \
  'state/design-system/<project-slug>/MASTER.md' \
  'state/design-system/<project-slug>/pages/<page-slug>.md' \
  'sefi-design-ignore: <reason>' \
  'state/motion-<slug>.md' \
  'SwiftUI' \
  'Expo' \
  'Approval: required' \
  'ThreeUI' \
  'React Bits' \
  'private addresses' \
  'PENDING' \
  'legacy flat design records'; do
  require_text docs/DESIGN-COUNCIL.md "$text"
done

require_text docs/MIGRATION-v0.9.0.md 'state/design-<slug>.md'
require_text docs/MIGRATION-v0.9.0.md 'not moved or deleted'

for source in \
  'Taste Skill' \
  'Emil Kowalski Skills' \
  'ThreeUI' \
  'Impeccable' \
  'Hallmark' \
  'React Bits' \
  'UI UX Pro Max'; do
  require_once CREDITS.md "$source"
done
for revision in \
  'e79ca9ec7e071eb3a3b623c4fb752e853fc3ed58' \
  '85e8e2363b713506e1d5b6e07a0eb2da66be1bc3' \
  '68802d5428071ada5c20db8094b1649e6bb770ed' \
  'f2c7051853848826aac2f4646581d62a732155ad' \
  '13ac0ec7e148655948100b6396439e481361d690' \
  '23b6d2c0ab10b949c7891b3e76b2f801dff186a3' \
  'de5f12b400775997d213524ef02a7c7d2746806f'; do
  require_text CREDITS.md "$revision"
done
require_text CREDITS.md 'MIT with Commons Clause'
require_text CREDITS.md 'does not vendor their prompts, datasets, components, or assets'

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo 'test-v09-documentation: PASS'
