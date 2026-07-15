# Roster -- full per-agent detail

Read on demand by sefi-orchestration; not inlined into the always-loaded body. One row per
agent file under `agents/`. Every agent additionally follows the anti-hallucination skill
(UNKNOWN/PENDING, verify-before-cite); it is not repeated per row.

| Agent (`agents/<file>`) | Model | Skills used | Gate / discipline | Cost tier |
|---|---|---|---|---|
| `engineering-manager.md` | sonnet | sefi-orchestration | routes and dispatches; never edits files | mid |
| `research-analyst.md` | haiku | memory-protocol | read-only; digest contract | cheap |
| `product-manager.md` | sonnet | loop-engineering | fixed heading skeleton; grep-countable steps | mid |
| `ui-ux-designer.md` | sonnet | frontend-design | four verbs (build/audit/redesign/study); direction-first; never pixel-clones | mid |
| `software-engineer.md` | sonnet | loop-engineering, backend-design, frontend-design | gate.sh before done; minimization ladder; vertical slices | mid |
| `qa-engineer.md` | opus | strategy-gate (rigor) | adversarial; executes to verify | high |
| `security-engineer.md` | opus | security-review | trust-boundary gate; read-only findings | high |
| `devops-engineer.md` | sonnet | loop-engineering | worktree procedure; honest telemetry; timeout classes | mid |
| `support-engineer.md` | haiku | loop-engineering | triage classes; consume-before-act | cheap |
| `knowledge-manager.md` | haiku | memory-protocol | append-only; single writer for `memory/` | cheap |
| `technical-writer.md` | haiku | technical-writing | verify-before-cite; honest claims only | cheap |
| `solutions-architect.md` | sonnet | n8n-workflow-design | locked ROI review; recommends only | mid |
| `quant-analyst.md` | sonnet | strategy-gate | hard gates; never loosens | mid |

## Growth
At 13 agents this roster sits just past the ~10-12 flat-folder boundary: it stays flat for
now, and the NEXT addition introduces a consistent file-name prefix (e.g. `build-*`,
`quality-*`) or domain subfolders under `agents/`. Keep this table the one source of truth
the router reads; a new agent is one appended row plus its file. The retro loop confirms an
improvement target is reachable by checking it is listed here.

## Scaling: roster.json sidecar pattern (future, at 20+ agents)
As the roster grows well past this table's comfortable size, consider adopting a
machine-readable `roster.json` sidecar read on-demand instead of hand-maintaining this
markdown table. The sidecar keeps sefi-orchestration/SKILL.md's always-loaded body flat
while a script queries agents/skills programmatically. Schema (one entry per agent):
`name`, `description`, `model`, `tools` (array), `skills` (array of skill names),
`agentic_signals` (boolean for each of goal_intake / refusal_gate / verification /
loop_discipline / close_out). Trigger adoption when: (a) this table exceeds ~30 rows, or
(b) a script needs to programmatically query agents/skills by name/tag. Until then, the
hand-maintained table above is sufficient and more readable.
