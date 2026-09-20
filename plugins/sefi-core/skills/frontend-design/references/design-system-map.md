# Design-System Decision Map

This independently written map keeps a design decision honest: use a documented official
ecosystem when the product requires it, otherwise build an owned token system. It does not
copy, bundle, or authorize third-party code, components, assets, palettes, prompts, or
templates.

## Decision rule

During BUILD Pass 1, inspect the target manifest and product constraints. If a named
ecosystem is already required, record its official package as a possible recommendation;
do not recreate a branded system from memory. If no ecosystem is required, record a native
CSS or existing project-component approach. Never mix two design systems in one product.

## Recommendation record

Recommend at most one external library only when it materially serves the selected direction
and task. Record exact package and version or `UNKNOWN`, project fit, selected capability,
bundle/performance cost, accessibility and reduced-motion behavior, License status, native
alternative, and `Approval: required`. No recommendation authorizes installation.

ThreeUI can be considered only for web work where 3D or shader-driven presentation is
central and its performance/accessibility costs are justified. React Bits can be considered
only for a React text, background, or interaction effect that fits the direction and is not
better as a small native implementation. Do not package their source, assets, shaders,
fonts, examples, or component code.

## Aesthetic decisions

An aesthetic is not an external component dependency. State the owned implementation choice,
its fallback, and why it serves the audience. For example, layered surfaces require a solid
fallback for transparency preferences, an editorial layout needs readable measure, and a
kinetic text treatment needs reduced-motion behavior. Keep direction, accessibility, and
performance decisions explicit.
