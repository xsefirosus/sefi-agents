---
name: motion-design
description: Use when a selected UI direction has nontrivial animation, transition interruption, focus behavior, or reduced-motion requirements.
managed-by: sefi-agents
---

# Motion Design

This craft skill governs temporal behavior after UI/UX Designer has selected a visual
direction. It does not choose or replace visual direction. All factual output follows the
anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Rule block
Craft skill. Use it only for motion that communicates hierarchy, continuity, feedback, or
state. Decorative motion requires an explicit design reason. Simple feedback can remain in
the design record; nontrivial motion uses Motion Designer and `state/motion-<slug>.md`.

1. Record Trigger, User purpose, Frequency, Properties animated, Duration, Easing or spring
   values, Transform origin, Interruption and cancellation behavior, Final semantic state,
   Focus behavior, Reduced-motion replacement, Touch behavior, Performance limit, Before,
   after, and reason evidence, and Rejected alternatives.
2. Prefer transform and opacity. Any other property needs a documented reason and performance
   limit. Do not use `transition: all`.
3. Interrupted input must leave correct content, focus, and semantic/programmatic state.
   Touch behavior includes cancellation and an equivalent keyboard operation.
4. Reduced motion preserves the final state and essential feedback without the temporal
   effect. Focus changes remain visible and deterministic.
5. Motion Designer cannot change layout, content, typography, branding, or the selected
   visual direction. Return a boundary finding to UI/UX Designer if a change is needed.

## Review
Audit each implemented motion for purpose, timing, easing/spring values, transform origin,
interruption result, focus result, reduced-motion result, and performance result. Report
pass or reject with evidence; unrun browser/device evidence is PENDING.
