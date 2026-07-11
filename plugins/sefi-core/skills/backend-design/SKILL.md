---
name: backend-design
description: Use when designing or building anything below the API seam -- endpoints, data models, migrations, background jobs, or service boundaries. Contract-first API design with trust-boundary validation, idempotent mutations, reversible migrations, and an explicit error taxonomy.
managed-by: sefi-agents
---

# Backend Design

Craft skill backing the software-engineer below the API seam. The expanded per-endpoint
checklist lives in `references/api-checklist.md`, read on demand.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never
guess (this includes API shapes -- quote the installed version's contract, never memory).

## Rule block
1. Contract first: the schema (request, response, errors) is written and agreed before
   the handler. The seam is the product; the handler is an implementation detail.
2. Validate at the trust boundary: every external input is validated where it enters
   (the handler), not deep inside where "it should already be clean." The UI is not a
   trust boundary.
3. Mutations are idempotent: a retried or double-delivered request must not double-act
   (idempotency key, upsert, or dedupe check). Assume every client retries.
4. Migrations are reversible and append-only: additive change first, backfill, then
   remove -- never a destructive change in the same step that deploys code depending on
   it. A migration without a down path is a finding.
5. Error taxonomy is explicit: 4xx for caller mistakes (with a machine-readable reason),
   5xx for our failures; no swallowed exceptions, no 200-with-error-body. Internal
   details never leak into client-facing errors.
6. Query discipline: no N+1 on a list path; pagination and limits by default on every
   collection endpoint; indexes stated for every new query pattern.
7. Secrets via environment or secret store, never code or repo config; connection
   strings are placeholders in examples (security-review rule 1 applies).
8. Observability at boundaries: structured log lines at entry/exit of each seam with
   outcome and duration -- stating what happened, never what was hoped (the honest-
   telemetry convention).

## Full-stack seam note
The software-engineer builds vertical slices: this skill governs below the seam,
frontend-design above it, and the contract (rule 1) IS the seam. Tests exist at each
layer plus one exercising the seam end to end.

See `references/api-checklist.md` for the per-endpoint checklist.

Self-test: every new endpoint has a written contract, boundary validation, an idempotency
story, a reversible migration, and a stated index for each new query.
