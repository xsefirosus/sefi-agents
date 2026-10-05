# Roster -- full per-agent detail

Read on demand by sefi-orchestration; not inlined into the model-invoked skill body, which loads only on description match (or deterministically via /sefi:route -- sefi-route on Hermes). Each Agent
value is a basename resolved to `agents/<basename>.md`. Every agent additionally follows the anti-hallucination skill
(UNKNOWN/PENDING, verify-before-cite); it is not repeated per row.

| Agent basename (`agents/<basename>.md`) | Tier | Skills used | Gate / discipline | Cost tier |
|---|---|---|---|---|
| `prompt-engineer` | low | sefi-orchestration | Stage 0, read-only; restates intent, never routes | cheap |
| `sefi-agents` | mid | sefi-orchestration | selects specialists, validates handoffs and budgets; never edits files | mid |
| `research-analyst` | low | memory-protocol | read-only; bounded general-context digest | cheap |
| `research-codebase-cartographer` | low | anti-hallucination | explicit map only; deterministic baseline, evidence graph, read-only target | cheap |
| `research-adoption-scout` | low | anti-hallucination | Cartographer -> Scout -> Product Manager; source/license/provenance decision only | cheap |
| `product-manager` | mid | loop-engineering, premortem (optional) | fixed heading skeleton; grep-countable steps | mid |
| `ui-ux-designer` | mid | frontend-design | five verbs including three-variant PROTOTYPE; direction-first; never pixel-clones | mid |
| `motion-designer` | mid | motion-design | nontrivial motion only; preserves UI/UX direction and product content | mid |
| `software-engineer` | mid | loop-engineering, backend-design, frontend-design | gate.sh before done; minimization ladder; vertical slices | mid |
| `qa-engineer` | high | anti-hallucination (bar-comparison) | adversarial; executes to verify | high |
| `security-engineer` | high | security-review | trust-boundary gate; read-only findings | high |
| `devops-engineer` | mid | loop-engineering | worktree procedure; honest telemetry; timeout classes | mid |
| `support-engineer` | low | loop-engineering | triage classes; consume-before-act | cheap |
| `memory-journalist` | low | memory-protocol | append-only; single writer for `memory/`; managed legacy migration | cheap |
| `technical-writer` | low | technical-writing | verify-before-cite; honest claims only | cheap |
| `solutions-architect` | mid | n8n-workflow-design, premortem (optional) | locked ROI review; recommends only | mid |
| `systems-auditor` | mid | anti-hallucination | reviewer-only; capped findings to one fenced report; never dispatches, never modifies source | mid |

## Growth
At 17 agents, this roster stays flat. The two scoped research roles use a research-
filename prefix, while a broad rename or domain-subfolder migration remains a separate
change. Keep this table the one source of truth the router reads; a new agent is one
appended row plus its file. The retro loop confirms an improvement target is reachable by
checking it is listed here.

## Scaling: roster.json sidecar pattern (future, at 20+ agents)
As the roster grows well past this table's comfortable size, consider adopting a
machine-readable `roster.json` sidecar read on-demand instead of hand-maintaining this
markdown table. The sidecar keeps sefi-orchestration/SKILL.md's model-invoked body flat
while a script queries agents/skills programmatically. Schema (one entry per agent):
`name`, `description`, `model`, `tools` (array), `skills` (array of skill names),
`agentic_signals` (boolean for each of goal_intake / refusal_gate / verification /
loop_discipline / close_out). Trigger adoption when: (a) this table exceeds ~30 rows, or
(b) a script needs to programmatically query agents/skills by name/tag. Until then, the
hand-maintained table above is sufficient and more readable.
