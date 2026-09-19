# Routing Table -- precedence-ordered, append-only

One dispatcher (sefi-agents) reads this table. Resolve the routing key
highest-to-lowest: per-message override -> per-project config (`sefi.config.yml`) ->
global default -> hardcoded fallback. Agent identity travels as a field. A new trigger or
loop is one appended row, never a new code branch.

Trigger column semantics: entries are semantic-intent descriptions, not literal substrings
or regexes -- a `/` separates independent aliases for the same row's intent, and a
paraphrase that clearly matches that intent (e.g. "check if it's solid before I merge"
matching the review/judge row) routes the same as an exact phrase. When intent is
genuinely ambiguous between two rows, that's a goal_intake case: ask, don't guess.

| Trigger | Default agent | Precedence-override fields | Special context flags |
|---|---|---|---|
| explicit "map codebase" / "trace codebase" / "change impact map" | research-codebase-cartographer | override: `agent` | target root + slug + entry points; read-only target; never route generic research here |
| explicit "evaluate adoption" / "evaluate reuse candidate" / "third-party adoption decision" | research-adoption-scout | override: `agent` | requires matching map; Cartographer -> Scout -> Product Manager; never route generic research here |
| "research X" / needs context | research-analyst | override: `agent` | -- |
| "plan X" / goal to spec | product-manager | override: `agent` | -- |
| "build / implement slice" | software-engineer | project: `engineer_model` | worktree required |
| "review / judge" / post-build | qa-engineer | project: `qa_model` | different model where possible |
| memory maintenance / weekly | memory-journalist | -- | -- |
| close_out / end of a loop cycle or work chunk | memory-journalist | -- | files durable observations; SKIP if none |
| "automate X" (n8n/Make/GHL) | solutions-architect | override: `agent` | -- |
| scheduled / CI trigger | (per loop spec) | -- | `skip_clarification`, `non_interactive` |
| multi-agent request / route it | sefi-agents | -- | -- |
| "design / UI / UX spec" | ui-ux-designer | override: `agent` | before any UI build |
| explicit "prototype three UI variants" / "keyboard picker prototype" | ui-ux-designer | override: `agent` | three isolated variants; selection before Product Manager planning |
| diff touches a trust boundary | security-engineer | -- | blocks PR on Critical |
| pipeline / release / worktree ops | devops-engineer | -- | -- |
| inbox item / issue intake | support-engineer | -- | consume-before-act |
| "write docs / changelog / guide" | technical-writer | override: `agent` | -- |
| UI audit / redesign / study a design reference | ui-ux-designer | override: `agent` | never pixel-clone in study |

The trigger source is itself routing and security context: a non-interactive or scheduled
trigger sets `skip_clarification` / `non_interactive` (scheduled runs drop clarification).
Append new rows below; never rewrite existing precedence.
