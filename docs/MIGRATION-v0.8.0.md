# Migrating to v0.8.0

This guide is for existing Sefi-Agents users moving to the local-first Memory Journalist
release.

## Upgrade each project

Install or update the plugin, open each project root, and run:

```text
/sefi:init
```

The command creates the new ignored `memory/sessions/` layout without overwriting an
existing memory file. It explains the optional local cross-project mirror. Leave it off
unless you want to search a specifically named related project on the same persistent
machine.

## What changed

- `knowledge-manager` is now `memory-journalist`, displayed as Memory Journalist.
- One substantial work session creates one structured session note.
- `/sefi:close-session` finishes a note safely and can be repeated.
- `/sefi:memory-index rebuild` recreates the local search cache from Markdown notes.
- `/sefi:cross-memory enable|disable|status` controls the opt-in local mirror.

An upgrade removes an old installed `knowledge-manager` agent file only when it has the
Sefi managed marker. A user-owned file is left untouched.

## Repository cleanup

Runtime `memory/` is now ignored at a project root and excluded from packages. Packaged
templates remain in `plugins/sefi-core/templates/memory/`.

The v0.8.0 release also rewrites public Git refs to remove the repository-root runtime
`memory/` history. This does not erase independent forks, existing clones, caches, or
downloaded archives. Fresh clones receive the cleaned history; existing clones should
follow their Git host's guidance for a rewritten branch or reclone.

GitHub may retain read-only refs for merged or closed pull requests. Branch and tag
force-pushes cannot rewrite those server-managed refs, so they remain a separate retention
boundary.

## New research commands

Use the Codebase Cartographer for evidence-backed repository maps:

```text
/sefi:map-codebase MAP
```

Use Adoption Scout to review external repositories without copying them or changing the
reviewed repository:

```text
/sefi:scout <source>...
```

The Product Manager decides whether an evidence-backed scout candidate belongs in a plan.
