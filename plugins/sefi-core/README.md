# sefi-core

The core plugin of sefi-agents: a loop-engineered, software-company-shaped agent team
with file-based persistent memory, hard token budgets, and CI-enforced anti-hallucination
discipline. See the repository root `README.md` for install and the tour; this file
describes the package layout.

## What ships here
- `agents/` -- 13 agents: engineering-manager, research-analyst, product-manager,
  ui-ux-designer, software-engineer, qa-engineer, security-engineer, devops-engineer,
  support-engineer, knowledge-manager, technical-writer, solutions-architect,
  quant-analyst. Each carries a `tools`/`disallowedTools` contract, a named model tier,
  and the anti-hallucination pointer (CI-enforced).
- `skills/` -- 12 skills: sefi-orchestration (the always-loaded router),
  anti-hallucination (the canonical no-invention rule), memory-protocol,
  loop-engineering, retro-improve, terse-mode, frontend-design, backend-design,
  security-review, technical-writing, n8n-workflow-design, strategy-gate. Deep material
  lives in each skill's `references/`, read on demand.
- `commands/` -- `/sefi:init`, `/sefi:triage`, `/sefi:retro`, `/sefi:status`,
  `/sefi:loop-new`.
- `hooks/hooks.json` -- a SessionStart hook that injects the memory router. Auto-loaded;
  do NOT also declare hooks in `plugin.json`.
- `scripts/` -- `gate.sh`, `compress-output.sh`, `inject-memory.sh`, `budget-check.sh`,
  `gen-router.sh`, plus the `ci/` validation suite (`run-all.sh` is the entry point).
- `templates/` -- copied into the user's project by `/sefi:init`: the memory vault, state
  ledger, inbox, two loop specs, config, and a GitHub Actions workflow. The plugin never
  owns project state; the project does.

## Design rules
- Generator/evaluator separation: the writer never grades its own work; the qa-engineer
  judges executed evidence.
- Anti-hallucination is structural: UNKNOWN/PENDING instead of plausible guesses, one
  canonical rule every agent and skill points to.
- Signature/Craft/Gate skills open with a `## Rule block`: a short, quotable checklist
  an agent's output contract can check, with deep material in `references/`, read on
  demand. This is sefi-agents' adaptation of the rules-vs-skills split (rules = what,
  skills = how) -- kept inside one file, not a parallel `rules/` tree, since Claude Code
  plugins cannot ship a top-level `rules/` directory.
- Single writer per artifact set; memory maintenance is append-only.
- Loops open PRs, never merge; the canonical rule is
  `skills/sefi-orchestration/references/human-checkpoint.md`.
- Zero runtime dependencies: markdown plus POSIX shell (git / rg / coreutils).

## Validate before a PR
```sh
bash scripts/ci/run-all.sh
```
