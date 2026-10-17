# Sefi router -- always-on global rule for Cline

Route every request through the `sefi-orchestration` skill before acting: follow
its Stage 0 and routing table, use the required skills and budgets, and dispatch
the specialists its route requires. A genuinely trivial request may use that
skill's documented exception. Explicit user instructions override this block.

`sefi-orchestration` is model-invoked, not automatic. When its auto-trigger does
not fire, load it deterministically with the `/sefi:route` command rather than
implementing the task directly.

Do not add `paths:` frontmatter to this file -- files without frontmatter are
always-on rules; a `paths:`-scoped rule only activates on matching context, so
scoping this router would silently drop routing for tasks that plainly need it.
Keep this file with no frontmatter block.

Hook status is UNKNOWN -- Cline has no confirmed session-start hook event this
repo can wire for sefi purposes, so this rules auto-load is the always-on
mechanism, not a hook. Do not invent a hooks config path.

Scripts referenced by routed skills resolve via `${CLAUDE_PLUGIN_ROOT}/scripts/`
(e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/check-handoff.sh` gates every dispatch);
the installer resolves that placeholder to the installed destination in copy
mode. Bundled agents, skills, and commands live alongside this rule under the
same installed root.
