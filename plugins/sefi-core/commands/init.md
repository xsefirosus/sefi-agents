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
   - `templates/state/retro-ledger.md` -> `state/retro-ledger.md`
   - `templates/state/` (placeholder) -> `state/`
   - `templates/inbox/` -> `inbox/`
   - `templates/loops/morning-triage.loop.md` -> `loops/morning-triage.loop.md`
   - `templates/loops/weekly-retro.loop.md` -> `loops/weekly-retro.loop.md`
   - `templates/loops/sync.loop.md` -> `loops/sync.loop.md`
   - `templates/config/sefi.config.yml` -> `config/sefi.config.yml`
   - `templates/config/budget.yml` -> `config/budget.yml`
3. Copy `templates/workflows/triage.yml` -> `.github/workflows/triage.yml` ONLY if the user
   confirms (it schedules a cloud job).
4. Copy `templates/hooks/pre-push` -> `.git/hooks/pre-push` and `chmod +x` it. Local-only
   (git never tracks `.git/hooks/`), so re-run this step after every fresh clone. Refuses
   a direct push to `main`/`master` -- the first deterministic backstop for
   human-checkpoint.md's never-auto-merge rule, which had none. State its real limit when
   reporting this step: a Bash-capable agent can still bypass it (`--no-verify`, or
   editing the file); the actual fix is a branch protection rule on the remote, which this
   cannot configure.
5. Worktree check-ignore gate: run `git check-ignore -q .worktrees`. If `.worktrees/` is not
   ignored, append it to `.gitignore` and commit before any loop creates a worktree. Create
   `.worktrees/logs/`.
6. `.gitignore` policy: `state/` and `inbox/` are committed by default; append them to
   `.gitignore` only if the user asks. `.worktrees/logs/` and `.sefi/` (step 7) are always
   ignored -- append `.sefi/` to `.gitignore` if it is not already covered.
7. Harness marker: write one line naming the harness you are running as right now (e.g.
   `claude`, `opencode`, `hermes`, `codex`) to `.sefi/harness` in the project root, creating
   the directory if needed. You already know this fact with certainty -- you are that
   harness's own agent executing this command -- so state it directly; never infer it from
   an environment variable or shell out to detect it. This is a machine-local install fact,
   not a vault note, which is why it lives outside `memory/` and `state/` and is always
   gitignored (step 6): `resolve-shared-memory-path.sh`'s caller reads it to name the
   cross-project memory mirror's files, falling back to `unknown-harness` if this step was
   ever skipped rather than failing.
8. Shared-install check: ask whether this install serves more than one project. `managed-by:
   sefi-agents` files (agents, skills) are installed once per user, not per project, so a
   retro loop in this project edits files every other project also loads. If the answer is
   yes -- or if this run is non-interactive and cannot ask -- set `improvement.enabled:
   false` in the copied `config/sefi.config.yml` and tell the user why: the retro loop still
   runs and still writes its proposed diff to `state/retro-<date>.md`, but a human applies it,
   so one project cannot silently rewrite another's agents. Leave `true` only when the user
   confirms this install serves this project alone.
9. Print next steps: open `memory/` in Obsidian; review `config/budget.yml`; try
   `/sefi:triage`.

## Guardrails
Never overwrite an existing file. Never open secret-bearing files. This command is
idempotent: a second run copies only what is missing.
`memory.vault_dir` in `config/sefi.config.yml` must stay the default relative `memory` path
scoped to this project. If a user asks to point it at an absolute or shared path (e.g. to
reuse one vault across multiple client repos), warn explicitly that this merges the two
projects' notes -- contradictions, promotions, and router links will cross-contaminate --
and require an explicit confirmation before proceeding.
`improvement.enabled` defaults to `true` in the template, which auto-applies retro edits to
the shared, user-global `managed-by: sefi-agents` files. That is safe only for a
single-project install. When in doubt, prefer `false`: it costs nothing but a human clicking
apply, and it is the only setting under which a shared install cannot cross-contaminate.
