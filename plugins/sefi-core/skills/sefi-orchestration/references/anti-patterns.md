# Authoring Anti-Patterns

Rules for writing agents and skills in this repo. Each is a mistake that looked reasonable
once and cost real diagnosis time.

- Don't duplicate skill content in agent files. An agent points at a skill; it does not
  re-explain it. Duplicated prose drifts out of sync and doubles the maintenance surface.
- Don't create agent dependencies. Agents are independent: each takes named input files
  and returns a digest. Agent A never imports or calls Agent B's internals; the
  orchestrator sequences them.
- Don't let a load-bearing shared rule live as ad hoc per-file copies. State it once in a
  reference (e.g. the never-auto-merge rule in `human-checkpoint.md`) and link it. N copies
  of a rule become N slightly-different rules.
- Don't inline a reference longer than ~100 lines into a SKILL body. Extract to
  `references/`; progressive disclosure keeps the always-loaded weight flat.
- Don't simulate tool enforcement with a hook that exits 0. That is enforcement theater;
  rely on the harness's real capability limits where they exist, and a soft contract
  elsewhere.
- Don't invent new agent frontmatter fields without documenting them. If you need a field
  beyond `name`/`description`/`tools`/`model`/`keywords`, add it to the schema and update
  this reference. Undocumented fields will rot.

Self-test: a shared rule appears exactly once; every other mention is a one-line link.
