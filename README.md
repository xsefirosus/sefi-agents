# sefi-agents

A portable team-in-a-box: markdown-defined agents, skills, loops, and a file-based
Obsidian-style memory vault, distributed as a Claude Code plugin that also runs on Hermes
Agent, OpenCode, and Codex. It implements loop engineering -- the repo does not just arm
single runs, it ships schedulable loops that discover work, hand it off, verify it, persist
state, and reschedule themselves, with a human checkpoint and hard budget caps. Zero runtime
dependencies: plain markdown plus POSIX shell.

## Install
```
/plugin marketplace add xsefirosus/sefi-agents
/plugin install sefi-core@sefi-agents
```
Then scaffold your project:
```
/sefi:init
```

### Have a coding agent set it up for you
Paste this to any coding agent:

> Help me set up sefi-agents by following
> https://raw.githubusercontent.com/xsefirosus/sefi-agents/main/Install.md

## 60-second tour

### Roster (7 agents)
| Agent | Use for |
|---|---|
| researcher | gather web/repo/doc context as a digest |
| planner | turn a goal into a checkable plan file |
| implementer | build one plan slice in a worktree |
| evaluator | adversarial PASS/REJECT against executed evidence |
| librarian | maintain the memory vault (append-only) |
| automation-architect | n8n / Make / GoHighLevel / RAG / Vapi specs |
| quant-analyst | trading-strategy gate and tier |

### Skills (7)
sefi-orchestration (routing brain), memory-protocol, loop-engineering, retro-improve,
terse-mode, n8n-workflow-design, strategy-gate.

### Loops (2)
- morning-triage -- daily discovery of failed CI, issues, and commits into draft PRs.
- weekly-retro -- single-writer self-improvement over the metrics ledger.

## Skills: user-invoked vs model-invoked
A user-invoked skill may invoke model-invoked skills, never another user-invoked one.

## Memory
The vault under `memory/` opens directly in Obsidian. Reads follow a router pattern:
frontmatter scan, then `memory/index.md`, then at most 2 wikilinks. To point at a heavier
backend later, see `docs/OPTIONAL-TOOLS.md`.

## Free-model mode
Runs reliably on a small free model (DeepSeek V4 Flash class). See `adapters/HERMES.md` for
the OpenCode Zen provider block and the live-verified local-gateway facts.

## Safety rails
- A separate adversarial evaluator judges PASS/REJECT against executed evidence -- the writer
  never grades its own work.
- Deterministic gates (`scripts/gate.sh`) run lint and tests; the LLM only does the creative
  step between them.
- Hard budget caps in `config/budget.yml`, enforced by `scripts/budget-check.sh`.
- Uncertain items land in `inbox/` for a human.
- Loops open PRs; they never merge. See
  `plugins/sefi-core/skills/sefi-orchestration/references/human-checkpoint.md`.

## Contributing
Run the CI suite before opening a PR:
```
bash plugins/sefi-core/scripts/ci/run-all.sh
```

## License
MIT. See `LICENSE`.
