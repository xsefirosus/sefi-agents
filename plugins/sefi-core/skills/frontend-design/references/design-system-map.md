# Design System Map -- brief signal to package or honest implementation

Adapted from Section 2 ("Brief -> Design System Map") of
https://github.com/Leonxlnx/taste-skill (MIT licensed), condensed to house style;
table content (package names, signals, rationale) preserved from the source.

Complements references/industry-patterns.md: that file names an aesthetic
*direction* per domain; this file names the actual package (or honest native-CSS
approach) once a direction is chosen. Consult during BUILD Pass 1 (token-system
planning), before committing to a component foundation. One system per project --
never mix two official design systems, and never import a component library into an
app themed by another.

## When the brief names or implies an existing product ecosystem
| Brief reads as | Reach for | Why |
|---|---|---|
| Microsoft / enterprise SaaS / dashboards | `@fluentui/react-components` or `@fluentui/web-components` | Official Fluent UI, Microsoft tokens, accessibility done |
| Google-ish UI, Material-flavored product | `@material/web` + Material 3 tokens | Official, theme-able via Material Theming |
| IBM-style B2B / enterprise analytics | `@carbon/react` + `@carbon/styles` | Official Carbon, mature data-density patterns |
| Shopify app surfaces | Polaris web components / Polaris React | Required for Shopify admin UI |
| Atlassian / Jira-style product | `@atlaskit/*` + `@atlaskit/tokens` | Official Atlassian design system |
| GitHub-style devtool / community page | `@primer/css` or `@primer/react-brand` | Official Primer; Brand variant for marketing |
| Public-sector UK service | `govuk-frontend` | Legally / regulatorily expected |
| US public-sector / trust-first | `uswds` | Same |
| Fast local-business / agency MVP | Bootstrap 5.3 | Boring, fast, works |
| Modern accessible React foundation | `@radix-ui/themes` | Primitives + polished theme |
| Modern SaaS where the team owns the components | shadcn/ui (`npx shadcn@latest add ...`) | Owned code, easy to customize -- never ship its default, un-themed state |
| Tailwind-based modern SaaS / AI marketing | Tailwind v4 utilities + `dark:` variant | Default for indie and small-team builds |

Install and use the official package for a system above; do not hand-recreate its
CSS, and do not import its tokens only to override most of them.

## When the brief is an aesthetic, not a shippable system
No single official package owns these -- build with native CSS, Tailwind, and a
maintained component library, and say in code comments what is borrowed inspiration
versus official material.

| Aesthetic | Honest implementation |
|---|---|
| Glassmorphism / "frosted glass" | `backdrop-filter`, layered borders, highlight overlays; solid-fill fallback for `prefers-reduced-transparency` |
| Bento (Apple-style tile grids) | CSS Grid with mixed cell sizes -- no library owns this |
| Brutalism | Native CSS, monospace, raw borders -- no library |
| Editorial / magazine | Serif type, asymmetric grid, generous whitespace -- no library |
| Dark tech / hacker | Mono plus accent neon, terminal motifs -- no library |
| Aurora / mesh gradients | SVG or layered radial gradients -- no library |
| Kinetic typography | Native CSS animations, scroll-driven animation, GSAP for hijacks -- no library |
| Apple "Liquid Glass" | Apple platforms only, no official web package -- `backdrop-filter` plus layered borders is an approximation; label it as one |

Self-test: a UI spec that names a design-system-map row also names which row and why,
in the same one-line rationale the direction-lanes stamp already requires.
