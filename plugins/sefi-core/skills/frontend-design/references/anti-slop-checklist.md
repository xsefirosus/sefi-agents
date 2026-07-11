# Anti-Slop Checklist -- the tells of generated-looking UI

Read before delivering any UI spec or build. Each tell is a concrete, checkable symptom;
two or more usually means the direction step was skipped. Fix the direction, not the
symptom.

## Layout tells
- The generic launch page: full-viewport hero, one-line slogan, three feature cards in a
  row, testimonial band, footer. If the layout could ship for any product, it ships for
  none.
- Every section the same width, same padding, same card treatment -- no rhythm, no
  emphasis, nothing is more important than anything else.
- Center-aligned everything, including long-form text.

## Style tells
- Default-palette gradient (violet-to-blue) on white, or the inverse dark hero, chosen
  by no one.
- One border-radius on every element regardless of size or role.
- Shadows inconsistent in direction or blur across components (no single light source).
- Emoji used as icons or section decoration.
- Icon sets mixed (outline next to filled next to duotone).

## Typography tells
- Browser-default or single-weight type doing all jobs; headings differ from body only
  by size.
- Line lengths over ~80 characters in body text.
- Title Case And Sentence case mixed across the same level.

## Content tells
- Placeholder-shaped copy: "Empower your workflow with seamless solutions."
- Feature names that describe nothing ("Smart. Simple. Secure.").
- Lorem ipsum or repeated filler visible in any delivered state.

## Interaction tells
- No designed empty, loading, or error states (the app looks fine only when full).
- Focus outline removed globally with nothing replacing it.
- Hover effects on non-interactive elements.

## Accessibility tells (automatic REJECT, not just slop)
- Text contrast below WCAG AA (4.5:1 body, 3:1 large text).
- Color as the only carrier of meaning (red/green status with no label or shape).
- Interactive targets under 44px with no spacing compensation.

## The counter-move
Name the direction, derive a type scale and spacing scale from it, define color roles
with measured ratios, design the empty state first, and delete one decorative element
per screen before delivery.
