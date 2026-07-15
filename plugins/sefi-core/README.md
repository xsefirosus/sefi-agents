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
- Tier gating: lighter agents (haiku-tier research-analyst, support-engineer) omit deep
  methodology sections; heavier agents (sonnet/opus-tier software-engineer, qa-engineer)
  include full behavioral rules and decision protocols. This keeps lightweight tasks
  token-efficient while ensuring complex decisions carry their full guard rails.
- Failure-mode justification in rules: when authoring a new principle or agent discipline,
  include a one-sentence link to the observed LLM failure it prevents (e.g., "This rule
  prevents unchecked assumptions" or "This gate prevents incomplete verification"). The
  "why" helps future maintainers understand scope and supports rule evolution.
- Single writer per artifact set; memory maintenance is append-only.
- Loops open PRs, never merge; the canonical rule is
  `skills/sefi-orchestration/references/human-checkpoint.md`.
- Zero runtime dependencies: markdown plus POSIX shell (git / rg / coreutils).

## Reference material extraction (supporting file threshold)
When writing a skill, decide whether reference material should live inline or in
`references/`: under 50 lines, keep it inline in the SKILL.md body (short lists,
examples, small decision tables belong where they're read); 50-100 lines is a judgment
call weighed against the skill's total line count (target <300 -- extract if adding it
would push the skill over 250 lines, inline is fine if the skill is still around 150);
over 100 lines always extract to `references/` and link it with "See
`references/<name>.md` for detail." This keeps skills scannable while preserving deep
material for readers who need it.

## Self-Test: How to Know This Is Working
Observable outcomes indicating these design rules are being followed:
- Plans specify verifiable done criteria and success measures before implementation
  starts.
- Diffs are minimal and every changed line traces to a concrete requirement or bug fix.
- Ambiguities surface early (goal-intake questions) rather than guessed at and
  implemented.
- PRs ship clean, focused changes without unrelated refactorings or speculative
  improvements.
- The qa-engineer rejects work lacking execution evidence; no "looks correct" approvals.
- Free-model dispatch succeeds more often because constraints are enforced in code, not
  promised in prompts.

## Validate before a PR
```sh
bash scripts/ci/run-all.sh
```
