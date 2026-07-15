---
description: Scaffold the current project with the sefi-agents memory vault, state ledger, inbox, loops, and config (skips existing files).
---

# /sefi:init

Scaffold this project so loops have somewhere to write. Copy templates from the plugin into
the project root, never overwriting existing files, and report what was skipped.

## Steps
1. Confirm you are at the intended project root, not inside the plugin cache.
2. Copy these template files into the project, creating parent directories, and SKIPPING
   any that already exist (report each skip):
   - `templates/memory/index.md` -> `memory/index.md`
   - `templates/memory/promotion-candidates.base` -> `memory/promotion-candidates.base`
   - `templates/memory/daily/` -> `memory/daily/`
   - `templates/memory/projects/` -> `memory/projects/`
   - `templates/memory/decisions/` -> `memory/decisions/`
   - `templates/memory/entities/` -> `memory/entities/`
   - `templates/state/metrics.md` -> `state/metrics.md`
   - `templates/state/` (placeholder) -> `state/`
   - `templates/inbox/` -> `inbox/`
   - `templates/loops/morning-triage.loop.md` -> `loops/morning-triage.loop.md`
   - `templates/loops/weekly-retro.loop.md` -> `loops/weekly-retro.loop.md`
   - `templates/config/sefi.config.yml` -> `config/sefi.config.yml`
   - `templates/config/budget.yml` -> `config/budget.yml`
3. Copy `templates/workflows/triage.yml` -> `.github/workflows/triage.yml` ONLY if the user
   confirms (it schedules a cloud job).
4. Worktree check-ignore gate: run `git check-ignore -q .worktrees`. If `.worktrees/` is not
   ignored, append it to `.gitignore` and commit before any loop creates a worktree. Create
   `.worktrees/logs/`.
5. `.gitignore` policy: `state/` and `inbox/` are committed by default; append them to
   `.gitignore` only if the user asks. `.worktrees/logs/` is always ignored.
6. Print next steps: open `memory/` in Obsidian; review `config/budget.yml`; try
   `/sefi:triage`.

## Guardrails
Never overwrite an existing file. Never open secret-bearing files. This command is
idempotent: a second run copies only what is missing.
`memory.vault_dir` in `config/sefi.config.yml` must stay the default relative `memory` path
scoped to this project. If a user asks to point it at an absolute or shared path (e.g. to
reuse one vault across multiple client repos), warn explicitly that this merges the two
projects' notes -- contradictions, promotions, and router links will cross-contaminate --
and require an explicit confirmation before proceeding.
