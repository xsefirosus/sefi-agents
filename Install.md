This file is for coding agents. If you are a human, use the README Quick Start instead.

## Goal
Get sefi-agents installed and `/sefi:init` run in the user's project via the least-risky
available path, then stop and report.

## Operating Rules
- Be idempotent: a second run changes nothing already in place.
- Never overwrite an existing config or memory file.
- No destructive action without explicit approval.
- Never open secret-bearing files, even to verify them. If a variable is missing, name it
  from its `config` placeholder (for example `$AGENT_API_KEY`) -- never read its value.
- sefi stores no credentials. Keys live in your harness config or your CI secrets, never in
  this tree, so there is nothing here to cache, stale, or invalidate: rotate at that source
  and no sefi file needs to change. The one exception is diagnostic, not stored state -- see
  the parse-ladder note in `skills/sefi-orchestration/SKILL.md`.
- Stop and report on any failure; do not attempt privileged installs.

## Success Criteria (know this before you start)
- [ ] The sefi-core plugin is installed, or the fallback `install.sh` has linked
      agents/skills/commands.
- [ ] `/sefi:init` has been run, so `memory/`, `state/`, `inbox/`, `loops/`, and `config/`
      exist in the project.
- [ ] `.worktrees/` is git-ignored and `.worktrees/logs/` exists.
- [ ] Nothing existing was overwritten.

## Steps (detect the environment, then branch)
1. Harness detection: is this Claude Code, Hermes, OpenCode, or Codex?
   - Claude Code: `/plugin marketplace add xsefirosus/sefi-agents` then
     `/plugin install sefi-core@sefi-agents`.
   - Hermes / OpenCode / Codex: use `./install.sh --target <hermes|opencode|claude>`; see the
     matching file under `adapters/`. If the required CLI is missing, stop and report.
2. Project state: is this a fresh repo or one with `.worktrees/` already present?
   - Fresh: proceed to `/sefi:init`.
   - Already scaffolded: run `/sefi:init` anyway; it copies only what is missing and reports
     skips.
3. Memory state: does `memory/index.md` already exist?
   - Yes: leave it; do not regenerate the router unless asked.
   - No: `/sefi:init` creates it from the template.
4. Worktree gate: ensure `.worktrees/` is git-ignored (add and commit if not) and create
   `.worktrees/logs/`.
5. If any required tool is missing at any branch, stop and report -- do not attempt a
   privileged install.

## Verification
- Confirm `memory/index.md`, `state/metrics.md`, `config/budget.yml`, and the two
  `loops/*.loop.md` exist.
- Confirm `git check-ignore -q .worktrees` succeeds.
- Confirm no pre-existing file was modified (only new files were added).

## Final Response Format (exactly 5 lines)
1. Setup path taken: <plugin | install.sh fallback>
2. Level reached: <installed+init done | installed only | blocked>
3. Files created or detected: <short list>
4. Remaining user action: <none | the one thing the user must do>
5. Exact next command: <e.g. /sefi:triage>

Stop at the setup boundary and report status -- do not continue into unrelated project work.
