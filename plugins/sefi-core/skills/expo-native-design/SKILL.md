---
name: expo-native-design
description: Use when designing or auditing an Expo or React Native interface after a UI direction is selected.
managed-by: sefi-agents
---

# Expo Native Design

Apply native mobile constraints to the selected UI direction. All factual output follows
the anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Rule block
Craft skill. Use only for Expo or React Native work; a normal web or SwiftUI request must
not load it. It does not install packages, does not invoke EAS services, and does not
change deployment configuration.

- Define Expo and React Native layout behavior with Safe-area handling, adaptive text, and
  resilient long content.
- Use Expo Router navigation patterns when the project uses Expo Router; state presentation,
  back behavior, deep-link implications, and focus/announcement needs.
- Specify touch targets, gestures, cancellation, Keyboard behavior, Screen-reader support,
  reduced motion, and no hover-only operation.
- Record Cross-platform differences for iOS, Android, and web where applicable. Do not
  assume a web pattern translates directly to native.
- Set list and animation performance limits, including virtualization or motion constraints
  when content scale requires them.
- For Web-to-native adaptation, retain user task and accessibility intent while changing
  controls and navigation to fit mobile conventions.

## Output
Add platform-specific decisions to the governing design record or page override. Never
choose a new direction or weaken shared accessibility, touch, motion, or content safeguards.
