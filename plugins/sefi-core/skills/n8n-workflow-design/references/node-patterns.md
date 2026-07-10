# n8n Node Patterns

Concrete wiring patterns, read on demand. These expand the Rule block in the skill body.

## Webhook -> validate -> process -> respond
Webhook node (POST) -> IF node verifying the signature or token -> process branch on true,
401 response on false. Never process an unverified webhook.

## Idempotent upsert
Compute a dedupe key from the payload -> lookup node -> IF exists: update; else: create. A
re-delivered event lands on the same row, not a duplicate.

## Retry with backoff and error branch
Set the node's retry-on-fail with an interval. Wire the node's error output to a dedicated
error branch that logs and notifies -- never a silent swallow.

## Observability
A final Set or HTTP node writes {run_id, status, duration, cost} to a log sink. This is the
one node that makes a failed run diagnosable after the fact.

## Notification (plain text)
Compose the message, then send with parse mode OFF. Model-authored text with `_` or `*`
breaks a Markdown or HTML parse and drops the whole message.

## Scope reminder
These patterns are for client and deliverable workflows. sefi-agents' own loops use direct
API calls, not n8n hops.
