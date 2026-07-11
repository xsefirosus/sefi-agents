---
name: frontend-design
description: Use when designing, building, auditing, or redesigning any user interface, or studying a design reference. The anti-AI-slop craft skill -- one committed aesthetic direction from a named lane catalog, typography-first hierarchy, a spacing system, tokens, designed states, and non-negotiable accessibility.
managed-by: sefi-agents
---

# Frontend Design -- anti-slop craft

Craft skill backing the ui-ux-designer and the software-engineer above the API seam.
The goal is UI that looks decided, not generated. Deep material lives in three
references, read on demand: references/direction-lanes.md (the named direction
catalog), references/anti-slop-checklist.md (the tells, in two tiers), and
references/industry-patterns.md (domain heuristics, illustrative only).

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never
guess (this includes design tokens -- never cite a token that is not in the spec).

## Rule block
1. Direction first: commit to ONE named aesthetic direction before any markup -- a
   lane from references/direction-lanes.md or an original named with the same rigor --
   with a one-line rationale tied to the audience. The default lane is restrained;
   immersive/maximalist is opt-in and requires the brief to ask for it. "Clean and
   modern" is the absence of a direction.
2. Typography carries the hierarchy: a deliberate type scale (not browser defaults),
   real hierarchy between heading levels, line lengths capped for reading. If the
   design works in grayscale, the hierarchy is real; if it needs color to read, it
   is not.
3. Spacing is a system: one scale in 0.25rem increments, applied everywhere. Ad-hoc
   pixel values are the tell that no system exists.
4. Color is restrained and intentional: defined color roles (surface, text, accent,
   danger) with contrast ratios stated; one accent doing real work beats five doing
   none. No default-gradient hero.
5. Design tokens over inline values: the spec defines tokens; the build consumes them.
   A value that appears twice un-tokenized is a finding.
6. States are designed, not defaulted: hover, focus, disabled, error, empty, and
   loading states specified per interactive component. The empty state is designed
   first. Loading uses skeleton screens over spinners; a mutation whose success is
   the overwhelmingly common case may update optimistically, with rollback on
   failure.
7. Motion only with purpose: animation communicates state change or hierarchy, never
   decoration; always with a reduced-motion fallback. Animate only transform and
   opacity; use will-change deliberately.
8. Accessibility is a gate, not polish: contrast >= WCAG AA, visible focus
   indicators, semantic HTML over ARIA-enhanced divs, aria-label on icon-only
   controls, explicit focus management in dialogs and dynamically revealed content,
   keyboard reachability, touch targets >= 44px. A beautiful inaccessible UI is a
   REJECT.
9. Concrete standards: mobile-first at the 320 / 768 / 1024 / 1440 breakpoints;
   hover-transition timing 150-300ms; icons from one SVG set (such as Heroicons or
   Lucide) -- never emoji as icons or decoration.
10. Domain awareness: references/industry-patterns.md lists conventional starting
    heuristics per domain (illustrative, not authoritative research); a brief that
    breaks convention should do so knowingly.

## Workflow (four verbs)
BUILD runs two passes: Pass 1 plans a token system (4-6 named colors, 2+ typefaces, a
layout concept, one signature element) with an ASCII wireframe; Pass 2 critiques that
plan against the brief, then specs the full system to state/design-<slug>.md. AUDIT
reads a built UI against its governing spec and reports numbered findings. REDESIGN is
BUILD with copy, information architecture, and brand marks preserved. STUDY extracts a
reference's DNA (macrostructure, type pairing, color roles) without pixel-cloning. The
full per-verb protocol lives in the ui-ux-designer agent; this skill is the craft it
applies.

Design stamp: the build places one comment near the stylesheet root naming the chosen
direction and the governing spec path, e.g. `/* direction: restrained -- spec:
state/design-checkout.md */`, so a later AUDIT can trace any built UI back to its
spec -- the design-side analog of this repo's wired-not-just-written rule.

Self-check against references/anti-slop-checklist.md before delivering any UI spec or
build.

Self-test: the delivered UI names its direction and spec path (the stamp), passes the
anti-slop checklist, and meets WCAG AA contrast with visible focus states.
