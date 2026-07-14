---
name: sefi-orchestration
description: Use when routing a request to the right agent, handing off between agents, or dispatching a subagent. The always-loaded routing brain covering roster, handoff rules, the parse ladder for structured output, model routing, and pointers to the harness map and never-auto-merge rule.
managed-by: sefi-agents
---

# Orchestration

The routing brain, loaded every turn. Keep this body a thin router; per-agent detail, the
harness map, and the routing table live in `references/` and are read on demand.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Roster (summary; full detail in `references/roster.md`)
| Agent | Use for | Cost |
|---|---|---|
| engineering-manager | route, dispatch, enforce contracts and budgets | sonnet |
| research-analyst | gather web/repo/doc context as a digest | haiku |
| product-manager | turn a goal into a checkable plan file | sonnet |
| ui-ux-designer | build, audit, redesign, or study a UI, direction-first | sonnet |
| software-engineer | build one full-stack plan slice in a worktree | sonnet |
| qa-engineer | adversarial PASS/REJECT against evidence | opus |
| security-engineer | security gate on diffs at trust boundaries | opus |
| devops-engineer | CI/CD, worktrees, scheduling, budget plumbing | sonnet |
| support-engineer | inbox/issue intake, triage, consume-before-act | haiku |
| knowledge-manager | vault distill / promote / router / contradiction | haiku |
| technical-writer | user-facing docs, changelogs, guides | haiku |
| solutions-architect | n8n / Make / GHL / RAG / Vapi specs | sonnet |
| quant-analyst | trading-strategy gate and tier | sonnet |

Read `references/roster.md` for each agent's skills, gates, and cost tier; do not inline
it here. At 13 files the roster sits just past the ~10-12 flat-folder boundary: it stays
flat, and the NEXT addition introduces a file-name prefix and domain subfolders.

## Dispatch (one dispatcher, table-driven)
The precedence-ordered trigger-to-agent map is `references/routing-table.md`. Resolve the
routing key highest-to-lowest: per-message override -> per-project config -> global
default -> hardcoded fallback. Agent identity travels as a field; a new trigger or loop is
one appended row, not new branching. A non-interactive or scheduled trigger sets
`skip_clarification` / `non_interactive`.

## Handoff rule
Each stage's output file must be self-contained. Name the specific upstream output file a
step consumes and inline all context the next agent needs; never write "as discussed
above." Every dispatched task names the absolute path (its worktree) it must write outputs
into, with one example joined path, e.g.
`/abs/project/.worktrees/feat-x/state/plan-feat-x.md`. A dispatched agent with no
designated output location writes to whatever its working directory happens to be, and the
verifier reading the designated folder sees nothing.

## Parse ladder (consume another agent's structured output)
Accept the payload anywhere in the reply, not only at position 0. Try in order:
1. the exact expected shape;
2. a fenced code block anywhere in the text (json-tagged or bare fences);
3. first-`{`-to-last-`}` extraction.

On failure, save the raw head and tail (~500 chars each) to `.worktrees/logs/` before
rejecting, so the failure is diagnosable. Free models routinely prefix structured output
with chat ("Here's the summary: ...").

## Discipline
- Output-contract enforcement: discard excess beyond a subagent's contract.
- Model routing: name every `model:`; an omitted model inherits the most expensive tier.
- The orchestrator never edits files; unfinished work is written to `state/`, never
  carried in context.
- Never open a file > 100 KB without a stated need; `rg` the needed slice instead.
- Genuinely trivial tasks: use judgment instead of applying full rigor mechanically --
  the one legitimate exception, and it never licenses skipping or relaxing a gate.

## References
- `references/roster.md` -- full per-agent detail (skills, gates, cost).
- `references/routing-table.md` -- precedence-ordered trigger-to-agent table.
- `references/harness-actions.md` -- the narrow harness action/tool/hook map.
- `references/human-checkpoint.md` -- the canonical never-auto-merge rule.
- `references/anti-patterns.md` -- authoring anti-patterns.
- `references/goal-intake.md` -- the canonical goal_intake behavior.

Self-test: every merge/deploy in a loop turn traces to an explicit human approval.
