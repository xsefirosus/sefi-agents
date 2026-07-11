# Anti-Slop Checklist -- the tells of generated-looking UI

Read before delivering any UI spec or build. Two or more tells usually mean the
direction step was skipped: fix the direction, not the symptom. Two tiers:
deterministic tells are numeric or keyword-checkable with no visual judgment; judgment
tells need an actual read of the design.

## Deterministic tier (mechanically checkable)
- Overused default fonts (Arial, Inter, system-ui) with no stated override rationale.
- One border-radius value on every element regardless of size or role.
- Touch targets under 44px with no spacing compensation.
- Text contrast below WCAG AA (4.5:1 body, 3:1 large text).
- No responsive rules at the standard breakpoints (320 / 768 / 1024 / 1440).
- Emoji used as icons or decoration (mirrors this repo's check-unicode-safety.sh
  philosophy: pictographs are not interface elements).
- Motion with no prefers-reduced-motion fallback.
- Focus outline removed globally with nothing replacing it.
- Animation of properties other than transform and opacity.

The accessibility items in this tier (contrast, touch targets, focus) are automatic
REJECTs, not style notes.

## Judgment tier (needs an actual read)

### Layout
- The generic launch page: full-viewport hero, one-line slogan, three feature cards in
  a row, testimonial band, footer. If the layout could ship for any product, it ships
  for none.
- Every section the same width, same padding, same card treatment -- no rhythm, no
  emphasis, nothing more important than anything else.
- Center-aligned everything, including long-form text.

### Style
- Default-palette gradient (violet-to-blue) on white, or the inverse dark hero, chosen
  by no one.
- Shadows inconsistent in direction or blur across components (no single light
  source).
- Icon sets mixed (outline next to filled next to duotone).
- Known AI-tell clusters -- defaults, not choices; avoid unless the brief asks:
  warm-cream + serif + terracotta; near-black + acid-green or vermilion accents;
  broadsheet layout + hairline dividers everywhere.

### Typography
- Browser-default or single-weight type doing all jobs; headings differ from body only
  by size.
- Line lengths over ~80 characters in body text.
- Title Case And Sentence case mixed across the same level.

### Content
- Placeholder-shaped copy: "Empower your workflow with seamless solutions."
- Feature names that describe nothing ("Smart. Simple. Secure.").
- Lorem ipsum or repeated filler visible in any delivered state.

### Interaction
- No designed empty, loading, or error states (the app looks fine only when full).
- Spinners where skeleton screens belong on content loads.
- Hover effects on non-interactive elements.
- Color as the only carrier of meaning (red/green status with no label or shape) --
  an accessibility REJECT, not a style note.

## The counter-move
Name the direction, derive a type scale and spacing scale from it, define color roles
with measured ratios, design the empty state first, stamp the direction and spec path
in the build, and delete one decorative element per screen before delivery.
