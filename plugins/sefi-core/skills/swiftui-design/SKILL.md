---
name: swiftui-design
description: Use when designing or auditing a SwiftUI or native Apple interface after a UI direction is selected.
managed-by: sefi-agents
---

# SwiftUI Design

Apply Apple-native interaction guidance without replacing the UI/UX Designer's direction.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Rule block
Craft skill. Use only for SwiftUI or native Apple work; a normal web or Expo request must
not load it. It guides a specification, does not install packages, does not invoke EAS
services, and does not change deployment configuration.

- Follow Apple platform conventions for navigation, presentation, safe areas, and native
  controls before inventing custom equivalents.
- Specify Dynamic Type reflow, VoiceOver labels/traits/order, Reduce Motion replacement,
  keyboard and focus behavior where supported, and at least 44pt touch targets.
- Define gestures with visible affordance, cancellation, final semantic state, and an
  accessible alternative. Avoid hover-only operation.
- Use platform-appropriate animation; state interruption behavior and performance limits.
- Cover iPhone and iPad layout behavior, including compact/regular adaptation, safe areas,
  long localized text, and resilient content.

## Output
Add Apple-specific decisions to the governing design record or page override. Do not select
a new direction, alter shared accessibility safeguards, or claim device testing not run.
