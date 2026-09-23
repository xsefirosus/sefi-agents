#!/usr/bin/env bash
# Offline documentation, provenance, and local-release checks for v0.9.0.
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

for file in docs/DESIGN-COUNCIL.md docs/MIGRATION-v0.9.0.md docs/RELEASE-v0.9.0.md; do
  require_file "$file"
done

for manifest in plugins/sefi-core/.claude-plugin/plugin.json plugins/sefi-core/.codex-plugin/plugin.json; do
  require_text "$manifest" '"version": "0.9.3"'
done
require_text .claude-plugin/marketplace.json '"version": "0.9.3"'
if [ "$(grep -Foc '"version": "0.9.3"' .claude-plugin/marketplace.json || true)" -ne 2 ]; then
  echo "FAIL: marketplace must carry v0.9.3 twice" >&2
  fail=1
fi

require_text README.md '16 AI agents'
require_text README.md 'The skills (19)'
require_text README.md 'Design Council'
require_text README.md 'Motion Designer'
require_text README.md 'docs/DESIGN-COUNCIL.md'
require_text Install.md 'v0.9.2'
require_text CHANGELOG.md '## [0.9.0] - 2026-09-20'
require_text docs/RELEASE-v0.9.0.md 'partially released'

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
