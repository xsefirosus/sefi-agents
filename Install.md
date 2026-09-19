This file is for coding agents. If you are a human, use the README Quick Start instead.

## Goal
Get sefi-agents installed via the least-risky available path, then clearly tell the user to
run `/sefi:init` once from the project root and stop. Do not initialize automatically:
installation is user-wide and the installer cannot safely choose the active project.

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
- [ ] The sefi-core plugin is installed, or the fallback installer has completed.
- [ ] On Codex, `$CODEX_HOME/AGENTS.md` contains the managed Sefi bootstrap block.
- [ ] The user has been told that `/sefi:init` must be run once from the intended project
      root to create private local memory, state, inbox, loops, and config files.
- [ ] `.worktrees/` is git-ignored and `.worktrees/logs/` exists.
- [ ] Nothing existing was overwritten.

## Steps (detect the environment, then branch)
1. Harness detection: is this Claude Code, Hermes, OpenCode, or Codex?
   - Claude Code: `/plugin marketplace add xsefirosus/sefi-agents` then
     `/plugin install sefi-core@sefi-agents`. The filesystem fallback is
     `./install.sh --target claude`.
   - Hermes: use `./install.sh --target hermes`; see `adapters/HERMES.md`.
   - OpenCode: use `./install.sh --target opencode`; see `adapters/OPENCODE.md`.
   - Codex: use `./install-codex.sh` (or `./install.sh --target codex`), then start a new
     session and accept Codex's one-time Sefi hook-trust prompt. This is a one-time
     installation action, not a command required for each prompt. See `adapters/CODEX.md`.
     If the required CLI is missing, stop and report.
   - A private or new harness may use `./install.sh --adapter path/to/adapter.yml` only
     with a complete local custom manifest. It is not a shipped or verified adapter until
     its adapter checks are added and pass.
2. Installation completion: state that installation succeeded, then give the exact next
   command: `/sefi:init` from the intended project root. Explain that it asks whether to
   enable optional cross-project memory, which remains local, private, and off by default.
   Do not run the command automatically unless the user explicitly asks you to initialize
   that project.
3. Memory state: does `memory/index.md` already exist?
   - Yes: leave it; do not regenerate the router unless asked.
   - No: `/sefi:init` creates it from the template.
4. Worktree gate: ensure `.worktrees/` is git-ignored (add and commit if not) and create
   `.worktrees/logs/`.
5. If any required tool is missing at any branch, stop and report -- do not attempt a
   privileged install.

## Verification
- Confirm the user received the exact project-root `/sefi:init` instruction.
- On Codex, confirm the managed Sefi block is present once in `$CODEX_HOME/AGENTS.md`.
- Confirm `git check-ignore -q .worktrees` succeeds.
- Confirm no pre-existing file was modified (only new files were added).

## Final Response Format (exactly 5 lines)
1. Setup path taken: <plugin | install.sh fallback>
2. Level reached: <installed -- init required | blocked>
3. Files created or detected: <short list>
4. Remaining user action: <none | the one thing the user must do>
5. Exact next command: <e.g. /sefi:triage>

Stop at the setup boundary and report status -- do not continue into unrelated project work.
