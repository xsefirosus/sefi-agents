# Prototype Protocol -- compare before committing

Use only for an explicit PROTOTYPE request. A prototype is a decision artifact; it does
not authorize application code, a dependency, or a new product direction.

## Variants and picker
Create exactly three isolated variants. Each records Direction, Product-context fit, Token
sketch, Controls demonstrated, Interaction behavior, Mobile behavior, Motion hypothesis,
Performance limit, Accessibility risks, Library requirement, and Review evidence. Do not
blend the variants before review. The picker visibly labels Variant 1, Variant 2, and
Variant 3; it shows one variant at a time; Tab reaches each choice, Arrow keys move the
active choice, Enter selects, and Escape exits without changing selection. The active
choice has a visible focus state, and reduced motion preserves the choice without animation.

## Review fields
The resulting state/design-prototype-<slug>.md contains:
- Motion plan -- trigger, purpose, properties, duration, easing, interruption, and
  reduced-motion behavior.
- Motion audit -- each motion, transform/opacity compliance, reduced-motion result,
  focus effect, and pass/reject.
- Review -- audience, direction, reviewer, date, selected variant or PENDING, mobile and
  a11y checks, library approval, and open questions.
- The selected variant becomes the design input for planning. The two rejected variants
  retain short rejection reasons and do not leak into the selected system.

## Mobile and library rule
Cover 320 / 768 / 1024 / 1440 breakpoints, env(safe-area-inset-*), 44px touch targets,
and direct manipulation with pointer feedback, cancellation, and keyboard equivalence.
After reading the target manifest, recommend at most one library with Approval: required;
state its installed version or UNKNOWN, fit, cost/maintenance concern, and native
alternative. The next agent waits for explicit user approval before adding it.

## Optional workbench
When useful, state/design-workbench-<slug>.html may host the picker and three variants
locally. It is disposable and does not share target application components, dependencies,
or production routes.
