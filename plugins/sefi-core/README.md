# sefi-core

The core plugin of sefi-agents: a loop-engineered agent team with file-based persistent
memory and hard token budgets. See the repository root `README.md` for install and the
60-second tour; this file describes the package layout.

## What ships here
- `agents/` -- 7 agents: researcher, planner, implementer, evaluator, librarian,
  automation-architect, quant-analyst. Each carries a `tools`/`disallowedTools` contract and
  a named model tier.
- `skills/` -- 7 skills: sefi-orchestration (the always-loaded router), memory-protocol,
  loop-engineering, retro-improve, terse-mode, n8n-workflow-design, strategy-gate. Deep
  material lives in each skill's `references/`, read on demand.
- `commands/` -- `/sefi:init`, `/sefi:triage`, `/sefi:retro`, `/sefi:status`,
  `/sefi:loop-new`.
- `hooks/hooks.json` -- a SessionStart hook that injects the memory router. Auto-loaded; do
  NOT also declare hooks in `plugin.json`.
- `scripts/` -- `gate.sh`, `compress-output.sh`, `inject-memory.sh`, `budget-check.sh`,
  `gen-router.sh`, plus the `ci/` validation suite (`run-all.sh` is the entry point).
- `templates/` -- copied into the user's project by `/sefi:init`: the memory vault, state
  ledger, inbox, two loop specs, config, and a GitHub Actions workflow. The plugin never
  owns project state; the project does.

## Design rules
- Generator/evaluator separation: the writer never grades its own work.
- Single writer per artifact set; memory maintenance is append-only.
- Loops open PRs, never merge; the canonical rule is
  `skills/sefi-orchestration/references/human-checkpoint.md`.
- Zero runtime dependencies: markdown plus POSIX shell (git / rg / coreutils).

## Validate before a PR
```sh
bash scripts/ci/run-all.sh
```
