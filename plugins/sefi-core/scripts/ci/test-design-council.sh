#!/usr/bin/env bash
# test-design-council.sh -- offline contract checks for the v0.9 Unified Design Council.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
UI="$CORE/agents/ui-ux-designer.md"
MOTION_AGENT="$CORE/agents/motion-designer.md"
FRONTEND="$CORE/skills/frontend-design"
MOTION="$CORE/skills/motion-design/SKILL.md"
SWIFTUI="$CORE/skills/swiftui-design/SKILL.md"
EXPO="$CORE/skills/expo-native-design/SKILL.md"
STYLE="$CORE/skills/design-style-profiles/SKILL.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }
declare -A normalized
has() {
  local subject="$1" needle="$2"
  if [[ ! -v "normalized[$subject]" ]]; then
    if [ -f "$subject" ]; then
      normalized["$subject"]="$(tr -s '[:space:]' ' ' < "$subject")"
    else
      normalized["$subject"]="$(find "$subject" -type f -exec cat {} + | tr -s '[:space:]' ' ')"
    fi
  fi
  printf '%s' "${normalized[$subject]}" | grep -qsF -- "$needle"
}
has_all() {
  local subject="$1" label="$2"
  shift 2
  local needle
  for needle in "$@"; do
    has "$subject" "$needle" || { bad "$label missing: $needle"; return; }
  done
  ok "$label"
}
absent() {
  if has "$1" "$2"; then bad "$3"; else ok "$3"; fi
}

has_all "$UI" 'UI/UX ownership and structured records' \
  'single owner of visual direction' 'Product Context' 'Selected Direction' \
  'Style Profile and Values' 'Resilient Content' 'Master and Page References' \
  'Evidence and Confidence' 'observed facts' 'design decisions' 'recommendations' 'unknown information'

has_all "$UI" 'persistent design-system inheritance' \
  'state/design-system/<project-slug>/MASTER.md' \
  'state/design-system/<project-slug>/pages/<page-slug>.md' \
  'more than one page or screen' 'multiple implementation tasks' \
  'may never weaken accessibility' 'Existing flat `state/design-<slug>.md` files remain readable'

has_all "$UI" 'conditional design routing and platform guidance' \
  'Motion Designer' 'motion-complexity: nontrivial' \
  'SwiftUI or native Apple work' 'Expo or React Native work' \
  'normal web design request must not load SwiftUI or Expo guidance'

has_all "$UI" 'prototype evidence and accessible picker' \
  'Product-context fit' 'Controls demonstrated' 'Performance limit' 'Review evidence' \
  'Tab' 'Arrow keys' 'Enter' 'Escape' 'reduced motion' 'rejection reasons'

has_all "$UI" 'conditional safe live-URL study' \
  'named public URL' 'read-only visual browser' 'same-domain resources' \
  'must not search the wider web' 'must not sign in' 'must not submit forms' \
  'must not download files' 'must not follow unrelated links' 'must not access private addresses' \
  'state/design-study-<slug>.md' 'PENDING' 'screenshot' 'untrusted input'

has_all "$FRONTEND" 'resilient-content and detector rules' \
  'Long URLs' 'browser zoom' 'text scaling' 'user spacing overrides' \
  'accessible `+n` disclosure' 'full-value path' 'Badge meaning' \
  'rapid input interrupts animation' 'transition: all' 'Placeholder-only form labels' \
  '100vh' 'sefi-design-ignore: <reason>'

has_all "$FRONTEND" 'domain guidance evidence fields' \
  'Product type' 'Common user priorities' 'Trust and accessibility concerns' \
  'Evidence type' 'Confidence' 'Review date'

has_all "$MOTION_AGENT" 'Motion Designer boundary and modes' \
  'PLAN' 'AUDIT' 'REDUCE' 'DIAGNOSE' 'cannot change layout, content, typography, branding, or the chosen visual direction' \
  'state/motion-<slug>.md'
has_all "$MOTION" 'motion record and reduced-motion contract' \
  'Transform origin' 'Interruption and cancellation behavior' 'Final semantic state' \
  'Reduced-motion replacement' 'Before, after, and reason evidence' 'Decorative motion requires an explicit design reason'

has_all "$SWIFTUI" 'SwiftUI design guidance' \
  'Apple platform conventions' 'Dynamic Type' 'VoiceOver' 'Reduce Motion' 'iPhone and iPad' \
  'does not install packages' 'does not invoke EAS services'
has_all "$EXPO" 'Expo native design guidance' \
  'Expo Router' 'Safe-area handling' 'Keyboard behavior' 'Screen-reader support' \
  'Cross-platform differences' 'does not install packages' 'does not change deployment configuration'
has_all "$STYLE" 'style profile constraints' \
  'Soft Premium' 'Minimal Editorial' 'Industrial Brutalist' 'Custom' \
  'Ornament' 'Information density' 'Contrast' '5 / 3 / 5' \
  'cannot choose a new direction' 'cannot replace the selected direction'

has_all "$UI" 'single-library approval record' \
  'at most one external library' 'ThreeUI' 'React Bits' 'exact package and version, or `UNKNOWN`' \
  'License status' 'Approval: required' 'No library is installed without explicit approval'

has_all "$MOTION_AGENT" 'motion agent preserves implementation boundary' \
  'never write target application code'

if [ "$fail" -ne 0 ]; then
  printf 'test-design-council: %s failed, %s passed\n' "$fail" "$pass"
  exit 1
fi
printf 'test-design-council: OK (%s passed)\n' "$pass"
