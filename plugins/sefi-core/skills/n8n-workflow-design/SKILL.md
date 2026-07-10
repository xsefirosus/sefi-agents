---
name: n8n-workflow-design
description: Use when designing an n8n or similar automation workflow as an implementable spec. Opens with the must-haves Rule block covering triggers, idempotency, retries, secrets, webhook security, observability, and cost-per-run, and points to references/node-patterns.md for deep patterns.
managed-by: sefi-agents
---

# n8n Workflow Design

Signature skill. This body is the Rule block the automation-architect's output contract
checks; deep node patterns live in `references/node-patterns.md`, read on demand.

User instructions always override this skill.

## Rule block (every workflow spec must cover)
1. Trigger inventory: every entry point (webhook, schedule, manual, event) named.
2. Idempotency: a re-delivered trigger must not double-act (dedupe key or upsert).
3. Retry and error branches: each external call has a retry policy and an error path.
4. Secrets handling: credentials via the platform's secret store, never inline.
5. Webhook security: signature or token verification on every inbound webhook.
6. Observability node: one node logs run outcome for diagnosis.
7. Cost-per-run estimate: state it, so the ROI review has a number.

## Standard spec output format
Trigger(s) -> nodes (in order) -> external calls -> error paths -> observability ->
cost-per-run. The automation-architect fills this shape into `state/automation-<slug>.md`.

## Two Sefi-OS-earned rules
- Model-authored notification text is sent plain, never through a Markdown or HTML parse
  mode. Arbitrary model text containing `_` or `*` silently kills a parsed send and drops
  the message entirely (observed live on a completion alert).
- Scope note: n8n is for client and deliverable workflows, never a hop inside sefi-agents'
  own control loop. Direct API calls beat four network hops plus an always-on service; a
  leftover n8n health probe generates permanent false alarms until deleted.

See `references/node-patterns.md` for concrete node wiring patterns.

Self-test: every external call in the spec has a retry policy and an error path.
