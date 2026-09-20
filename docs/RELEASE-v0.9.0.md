# v0.9.0 Release Notes

v0.9.0 adds the Unified Design Council: a Motion Designer, conditional SwiftUI and Expo
guidance, style profiles, persistent design-system records, and stronger resilient-content
review. The release remains local-first, offline-testable, and dependency-free.

## Design Council

- UI/UX Designer remains the sole owner of visual direction.
- Motion Designer plans and audits nontrivial temporal behavior without changing direction,
  layout, content, typography, or brand.
- motion-design, swiftui-design, expo-native-design, and design-style-profiles extend the
  skill catalog. SwiftUI and Expo guidance load only for its platform.
- Reusable products can use a shared MASTER.md with minimal page overrides.
- Task receipts add Product Context, evidence, confidence, motion complexity, resilient
  content, and library decisions.

## Safer interface review

The design contract covers reflow, long content, zoom, text scaling, wrapping chips and
badges, accessible truncation, non-color status meaning, focus, interrupted input, safe
areas, Dynamic Type, and reduced motion. The three-variant prototype picker remains
keyboard-accessible and respects reduced motion.

## Studies and libraries

Public URL studies are visual, read-only, same-domain inspections with no-search,
no-sign-in, no-form, no-download, no-unrelated-navigation, and no-private-address
boundaries. Browser-unavailable studies are PENDING until a screenshot is supplied.

ThreeUI and React Bits remain recommendation-only. Each recommendation needs manifest
inspection, one-library-per-task discipline, license and performance review, an accessible
alternative, and Approval: required. No external library is installed or vendored by this
release.

## Release status

This working tree is partially released: local package metadata, documentation, and the
release ledger are prepared for v0.9.0. A v0.9.0 tag, published GitHub release, and public
marketplace index require independent publication evidence before the release can be called
released. Run the local CI suite and fresh-install fixtures for Claude Code, Codex, OpenCode,
and Hermes before publication.

Read DESIGN-COUNCIL.md and MIGRATION-v0.9.0.md for operational details.
