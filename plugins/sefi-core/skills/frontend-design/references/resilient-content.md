# Resilient Content and Interaction

Design for headings and body text that reflow naturally. Long URLs, identifiers, filenames,
and untranslated strings wrap safely. Support browser zoom, text scaling, and user spacing
overrides without losing controls or meaning.

Chips, tags, and badges wrap or use an accessible `+n` disclosure. When truncation is
unavoidable, expose an accessible full-value path. Badge meaning never depends on color
alone. Interactive chips use native semantics, visible focus, keyboard operation, and
programmatic state.

When rapid input interrupts animation, correct content, focus, and semantic state win over
the unfinished transition. Use mobile safe areas, Dynamic Type where applicable, touch
targets of at least 44px, and no hover-only operation.

High-confidence detectors are `transition: all`, removed focus outlines without a
replacement, placeholder-only form labels, emoji used as controls, `100vh` without a safer
viewport strategy, and motion without reduced-motion handling. Suppress only with a nearby
`sefi-design-ignore: <reason>` marker; explain the exception and preserve the underlying
accessibility requirement.
