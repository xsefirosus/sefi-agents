# Loop metrics -- machine bookkeeping. Appended by loops (one row per qa-engineer verdict), read by retro-improve. Never hand-edited; append-only.
<!-- target-path = plugin-relative path of the agent/skill involved: the SAME path retro-improve would edit (single keyspace by construction) -->
<!-- route = the post-dispatch check-route.sh status for the row's dispatch; match / mismatch / invalid are now LIVE for Codex dispatches (check-route.sh reads the session rollout); unavailable on claude-code and not-applicable on opencode/hermes remain expected; skipped when check-route.sh exits 3 (no python3/python 3.11+ interpreter available) -- the check did not run, it does NOT block or STOP (skipped != mismatch); n/a when the row records no dispatch (e.g. a retro or manual entry) -->
<!-- a mismatch means the orchestrator stopped and parked the item in inbox/ -->
| date | target-path | loop | verdict | retries | note | route |
|------|-------------|------|---------|---------|------|-------|
