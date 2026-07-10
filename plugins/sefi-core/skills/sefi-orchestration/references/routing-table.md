# Routing Table -- precedence-ordered, append-only

One dispatcher reads this table. Resolve the routing key highest-to-lowest: per-message
override -> per-project config (`sefi.config.yml`) -> global default -> hardcoded fallback.
Agent identity travels as a field. A new trigger or loop is one appended row, never a new
code branch.

| Trigger | Default agent | Precedence-override fields | Special context flags |
|---|---|---|---|
| "research X" / needs context | researcher | override: `agent` | -- |
| "plan X" / goal to spec | planner | override: `agent` | -- |
| "build / implement slice" | implementer | project: `implementer_model` | worktree required |
| "review / judge" / post-build | evaluator | project: `evaluator_model` | different model where possible |
| memory maintenance / weekly | librarian | -- | -- |
| "automate X" (n8n/Make/GHL) | automation-architect | override: `agent` | -- |
| trading-strategy artifact | quant-analyst | -- | -- |
| scheduled / CI trigger | (per loop spec) | -- | `skip_clarification`, `non_interactive` |

The trigger source is itself routing and security context: a non-interactive or scheduled
trigger sets `skip_clarification` / `non_interactive` (scheduled runs drop clarification).
Append new rows below; never rewrite existing precedence.
