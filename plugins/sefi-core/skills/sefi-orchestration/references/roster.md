# Roster -- full per-agent detail

Read on demand by sefi-orchestration; not inlined into the always-loaded body. One row per
agent file under `agents/`.

| Agent (`agents/<file>`) | Model | Skills used | Gate / discipline | Cost tier |
|---|---|---|---|---|
| `researcher.md` | haiku | memory-protocol | read-only; digest contract | cheap |
| `planner.md` | sonnet | loop-engineering | fixed heading skeleton; grep-countable steps | mid |
| `implementer.md` | sonnet | loop-engineering, terse-mode | gate.sh before done; minimization ladder | mid |
| `evaluator.md` | opus | strategy-gate (rigor) | adversarial; executes to verify | high |
| `librarian.md` | haiku | memory-protocol | append-only; single writer for `memory/` | cheap |
| `automation-architect.md` | sonnet | n8n-workflow-design | locked ROI review; recommends only | mid |
| `quant-analyst.md` | sonnet | strategy-gate | hard gates; never loosens | mid |

## Growth
When this roster exceeds ~10-12 agents, introduce a consistent agent-file prefix (e.g.
`research-*`, `build-*`) and domain subfolders under `agents/`. Keep this table the one
source of truth the router reads; a new agent is one appended row plus its file. The retro
loop confirms an improvement target is reachable by checking it is listed here.
