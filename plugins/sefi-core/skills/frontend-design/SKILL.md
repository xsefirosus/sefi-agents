---
name: frontend-design
description: Use when designing or building any user interface: pages, components, dashboards, or emails. The anti-AI-slop craft skill requiring one committed aesthetic direction, typography-first hierarchy, a spacing system, restrained intentional color, and non-negotiable accessibility.
managed-by: sefi-agents
---

# Frontend Design -- anti-slop craft

Craft skill backing the ui-ux-designer and the software-engineer above the API seam. The
goal is UI that looks decided, not generated. The concrete slop-tells list lives in
`references/anti-slop-checklist.md`, read before delivering any UI.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never
guess (this includes design tokens -- never cite a token that is not in the spec).

## Rule block
1. Direction first: commit to ONE named aesthetic direction before any markup, with a
   one-line rationale tied to the audience (e.g. "dense editorial, because operators
   scan tables all day"). "Clean and modern" is the absence of a direction. Every later
   choice must be defensible from the direction.
2. Typography carries the hierarchy: a deliberate type scale (not browser defaults),
   real hierarchy between heading levels, line lengths capped for reading. If the design
   works in grayscale, the hierarchy is real; if it needs color to read, it is not.
3. Spacing is a system: one scale (e.g. 4/8-based), applied everywhere. Ad-hoc pixel
   values are the tell that no system exists.
4. Color is restrained and intentional: defined color roles (surface, text, accent,
   danger) with contrast ratios stated; one accent doing real work beats five doing
   none. No default-gradient hero, no emoji as decoration.
5. Design tokens over inline values: the spec defines tokens; the build consumes them.
   A value that appears twice un-tokenized is a finding.
6. States are designed, not defaulted: hover, focus, disabled, error, empty, and loading
   states specified per interactive component. The empty state is designed first -- it
   is what a new user actually sees.
7. Motion only with purpose: animation communicates state change or hierarchy, never
   decoration; always with a reduced-motion fallback.
8. Accessibility is a gate, not polish: contrast >= WCAG AA, visible focus indicators,
   semantic HTML structure, keyboard reachability, touch targets >= 44px. A beautiful
   inaccessible UI is a REJECT.

## Workflow
Design (ui-ux-designer): direction -> system (type/spacing/color/states) -> spec to
state/design-<slug>.md -> slop-tells self-check. Build (software-engineer): consume the
spec's tokens; deviations are findings in review, judged against the spec line by line.

See `references/anti-slop-checklist.md` for the tells that mark generated-looking UI.

Self-test: the delivered UI names its direction, passes the slop-tells checklist, and
meets WCAG AA contrast with visible focus states.
