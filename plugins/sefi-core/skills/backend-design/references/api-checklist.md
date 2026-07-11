# API Checklist -- per-endpoint detail

Read on demand by the backend-design skill. Run every new or changed endpoint through
all sections.

## Contract
- Request and response schemas written (types, required/optional, examples).
- Error responses enumerated with machine-readable codes, not prose-only.
- Versioning story stated (path, header, or additive-only).
- Backward compatibility: removed or renamed fields go through deprecation, never a
  silent break.

## Validation (at the boundary)
- Types, ranges, lengths, and formats checked in the handler layer.
- Unknown fields rejected or explicitly ignored (documented which).
- IDs authorized, not just parsed: "exists" is not "yours."

## Idempotency and concurrency
- POST/PUT/PATCH carry an idempotency key or upsert semantics.
- Concurrent double-submit tested (two requests, one effect).
- Long operations return a job handle instead of holding the connection.

## Data and migrations
- Additive migration first; backfill separately; destructive step last and gated.
- Down migration written and tested against a copy.
- New query patterns list their index; EXPLAIN checked on realistic data volume.
- Collection endpoints paginate with a default and a maximum page size.

## Errors and resilience
- External calls have timeouts, a retry policy with backoff, and a failure branch.
- Partial failure paths return a consistent state, never half-committed effects.
- 4xx vs 5xx separation tested; internal messages never reach the client.

## Observability
- Entry/exit structured logs: route, outcome, duration, caller id (no PII, no secrets).
- One metric or log line per failure branch, derived from the parsed result (honest
  telemetry -- never emit success from substring absence).

## Background jobs
- Jobs are idempotent and resumable (the loop-engineering resume-block pattern applies).
- A dead-letter path exists; a poisoned message cannot wedge the queue.
