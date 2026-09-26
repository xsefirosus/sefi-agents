---
description: Initialize Sefi in the current project root with private local memory, state, loops, and configuration.
---

# /sefi:init

Run this once from the project root you intend to work in. Installation is user-wide, so
an installer cannot safely choose a repository or modify it automatically.

Copy packaged templates without overwriting an existing file, and report every skipped
file:

- `templates/memory/index.md` to `memory/index.md`
- `templates/memory/sessions/` to `memory/sessions/`
- `templates/memory/promotion-candidates.base` to `memory/promotion-candidates.base`
- `templates/state/metrics.md` to `state/metrics.md`
- `templates/state/retro-ledger.md` to `state/retro-ledger.md`
- `templates/inbox/` to `inbox/`
- `templates/audits/` to `audits/`
- `templates/loops/morning-triage.loop.md` to `loops/morning-triage.loop.md`
- `templates/loops/sync.loop.md` to `loops/sync.loop.md`
- `templates/loops/weekly-retro.loop.md` to `loops/weekly-retro.loop.md`
- `templates/config/budget.yml` to `config/budget.yml`
- `templates/config/sefi.config.yml` to `config/sefi.config.yml`

Create `.sefi/` and `.worktrees/logs/` locally. Add `memory/`, `audits/`, `.sefi/`, and
`.worktrees/logs/` to `.gitignore` only when absent. Runtime memory and audit reports
are private, local, and never committed. The packaged `plugins/sefi-core/templates/memory/`
and `templates/audits/` sources remain part of the plugin.

If interactive, explain that cross-project memory is optional, local to the current OS
user, and off by default. Ask whether to enable it. Set
`memory.cross_project_enabled: true` only after an explicit yes. In a non-interactive
initialization must keep `cross_project_enabled: false`. Preserve an existing config and
report its value rather than changing it.

Optionally copy `templates/workflows/triage.yml` only after the user confirms because it
creates a cloud job. Copy `templates/hooks/pre-push` only when it does not replace an
existing hook. A hook is not a security boundary and can be bypassed; remote branch
protection is separate.

Finish by confirming that initialization succeeded for this project root. Explain that
`/sefi:audit <scope>` runs on demand and writes its ignored-local report under
`audits/`. Then point the user to `/sefi:close-session`,
`/sefi:memory-search <query>`, and `/sefi:memory-index rebuild`.

Never auto-initialize during a user-wide install, overwrite a user file, read a
secret-bearing file, or make cross-project memory ambient. This command is idempotent.
