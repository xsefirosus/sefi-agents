# Migrating to v0.9.0

This guide is for existing Sefi-Agents users adding the Unified Design Council.

## Keep existing task records

Legacy flat design records at state/design-<slug>.md remain readable. They are not moved or deleted.
Continue using a flat record for a single page or a disposable prototype.

## Add a reusable system only when needed

Create state/design-system/<project-slug>/MASTER.md when a product has several pages or
screens, repeated implementation tasks share visual rules, or you request a reusable
design system. Add pages/<page-slug>.md only for intentional page differences. The page
record cannot weaken the master accessibility, keyboard, touch-target, reduced-motion, or
resilient-content requirements.

## New conditional guidance

v0.9.0 adds Motion Designer and motion-design, swiftui-design, expo-native-design, and
design-style-profiles. SwiftUI and Expo guidance is conditional on its platform; ordinary
web work does not load either. Motion Designer is used for nontrivial motion and writes
state/motion-<slug>.md.

Each new BUILD, REDESIGN, or PROTOTYPE record has one Product Context block and exactly one
selected direction and style profile. Existing records do not need a retroactive rewrite.

## Optional recommendations remain optional

ThreeUI and React Bits can be recommended only after target-manifest inspection, at most
one library per task, and with Approval: required. Updating Sefi does not install either
library or add third-party source, assets, shaders, fonts, examples, or components.

Read DESIGN-COUNCIL.md for complete record, prototype, resilience, study, and library
rules.
