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
| Agent | Use for | Tier |
|---|---|---|
| sefi-agents | route, dispatch, enforce contracts and budgets | mid |
| research-analyst | gather web/repo/doc context as a digest | low |
| product-manager | turn a goal into a checkable plan file | mid |
| ui-ux-designer | build, audit, redesign, or study a UI, direction-first | mid |
| software-engineer | build one full-stack plan slice in a worktree | mid |
| qa-engineer | adversarial PASS/REJECT against evidence | high |
| security-engineer | security gate on diffs at trust boundaries | high |
| devops-engineer | CI/CD, worktrees, scheduling, budget plumbing | mid |
| support-engineer | inbox/issue intake, triage, consume-before-act | low |
| knowledge-manager | vault distill / promote / router / contradiction | low |
| technical-writer | user-facing docs, changelogs, guides | low |
| solutions-architect | n8n / Make / GHL / RAG / Vapi specs | mid |
| prompt-engineer | Stage 0 -- restate a raw human message before routing | low |

Read `references/roster.md` for each agent's skills, gates, and cost tier; do not inline
it here. At 13 files the roster sits past the ~10-12 flat-folder boundary: it stays flat
for now, and the NEXT addition introduces a file-name prefix and domain subfolders.

## Dispatch (one dispatcher, table-driven)
Stage 0: an interactive human message passes through `prompt-engineer` first -- it
restates the raw message into single-intent statements plus stated constraints, and
attaches a non-binding suggested row. The sefi-agents then resolves the restated
intent(s) against the table below. Skipped entirely on a non-interactive or scheduled
trigger; the raw trigger reaches the table unchanged.

The precedence-ordered trigger-to-agent map is `references/routing-table.md`. Resolve the
routing key highest-to-lowest: per-message override -> per-project config -> global
default -> hardcoded fallback. Agent identity travels as a field; a new trigger or loop is
one appended row, not new branching. A non-interactive or scheduled trigger sets
`skip_clarification` / `non_interactive`.

## Model dispatch

Resolve the orchestrator and every role tier through
`${CLAUDE_PLUGIN_ROOT}/scripts/model-for.sh` and `config/model-map.yml`; do not duplicate
provider identifiers in prompts or this skill. For Claude orchestration, request the
configured high effort through that contract. Start with the configured orchestrator
mapping. Retry exactly once only when the harness reports the primary model unavailable:
call `model-for.sh claude-code orchestrator --fallback --failure-class model-unavailable
--attempt 1 --retry-state <absolute-per-dispatch-log-path>`. That command atomically
consumes the state path, rejecting a second attempt and every other failure class. Do not
retry or switch models for any other failure, and do not claim a model is account-available
before the harness runs.

## Handoff rule
Each stage's output file must be self-contained. Name the specific upstream output file a
step consumes and inline all context the next agent needs; never write "as discussed
above." Every dispatched task names the absolute path (its worktree) it must write outputs
into, with one example joined path, e.g.
`/abs/project/.worktrees/feat-x/state/plan-feat-x.md`. A dispatched agent with no
designated output location writes to whatever its working directory happens to be, and the
verifier reading the designated folder sees nothing.

Write the handoff as an envelope and gate it before dispatching -- the rule above is
deterministic, so it is checked by a script rather than trusted:
```
agent:   software-engineer
reads:   state/plan-feat-x.md
writes:  /abs/project/.worktrees/feat-x
budget:  dispatch
context: <inlined; must stand alone on the receiving side>
```
`${CLAUDE_PLUGIN_ROOT}/scripts/check-handoff.sh <envelope>` exits nonzero on a relative `writes:` path, an empty
`reads:` or `context:`, a back-reference such as "as discussed above", or an agent slug
that resolves to no file. A blocked envelope is fixed and re-checked, never dispatched
anyway. Plans have had `${CLAUDE_PLUGIN_ROOT}/scripts/validate-plan-structure.sh` for a while; handoffs fail more
expensively and had only prose until this gate.

## Parse ladder (consume another agent's structured output)
Accept the payload anywhere in the reply, not only at position 0. Try in order:
1. the exact expected shape;
2. a fenced code block anywhere in the text (json-tagged or bare fences);
3. first-`{`-to-last-`}` extraction.

On failure, save the raw head and tail (~500 chars each) to `.worktrees/logs/` before
rejecting, so the failure is diagnosable. That dump is raw and unfiltered by design -- the
memory-protocol privacy filter guards vault writes, and running it here would strip the very
bytes the dump exists to show. `.worktrees/logs/` is always gitignored (`/sefi:init` step 5),
so a dump never reaches the repo; treat it as local diagnostic output that may contain
whatever the model echoed. Free models routinely prefix structured output
with chat ("Here's the summary: ...").

## Discipline
- Output-contract enforcement: discard excess beyond a subagent's contract; a dispatched
  agent's returned digest stays within `per_agent_return_tokens` (config/budget.yml).
- Model routing: name every `model:`; an omitted model inherits the most expensive tier.
- Route evidence: after each dispatch run `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh <harness> <tier> <session-record-or-thread-id>` and record its status in the `state/metrics.md` `route` column. On Codex the comparison is LIVE (`match` / `mismatch` / `invalid` per the rollout); `unavailable` / `not-applicable` is expected on claude-code / opencode / hermes. On `mismatch` (Codex ran a different model/effort than the tier map asked for) STOP, park the item in `inbox/`, never accept the run. If the shim exits 3 (no `python3` / `python` 3.11+ interpreter), record `route` as `skipped` -- the check did not run; it does not block or STOP.
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
- `references/scope-boundary.md` -- produce your own deliverable, never another agent's;
  gated on the dispatched path by `${CLAUDE_PLUGIN_ROOT}/scripts/check-reply.sh`.
- `references/close-out.md` -- the canonical close_out behavior, and the vault's only
  producer: the knowledge-manager dispatch that files a cycle's durable observations.
- `references/refusal-gate.md` -- the canonical refusal_gate behavior.
- `references/verification.md` -- the canonical verification behavior.
- `references/loop-discipline.md` -- the canonical loop_discipline behavior.
- `docs/BUDGET.md` -- the token-discipline stack, biggest lever first; terse-mode (output
  compression) is last and smallest on purpose -- check the bigger levers before reaching
  for it.

Self-test: every merge/deploy in a loop turn traces to an explicit human approval.
