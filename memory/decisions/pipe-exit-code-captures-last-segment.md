---
tags: [decision, shell, pitfall]
type: tricky-gotcha
status: active
date-discovered: 2026-09-03
evidence: astral-adoption Phase 3, Phase 4 route verification cycles
scope: all
---

# Pipe Exit Code Captures Last Segment, Not First

## The Rule

In a shell pipeline, `$?` captures the exit code of the LAST command, not the first one.

To capture the exit code of the first command in a pipeline:
- Re-run it without the pipe, OR
- Use `set -o pipefail` (bash/zsh) + `${PIPESTATUS[0]}` (bash), or `$pipestatus[1]` (zsh).

## Why It Matters

A silently-failing check buried in a pipe may appear to succeed. You waste cycles debugging the wrong part of the system.

Example: `check-route.sh | tail` -- if the check fails but `tail` succeeds, `$?` is 0, so you think the check passed.

## Evidence From Astral-Adoption Run

**Phase 3 and Phase 4**, multiple verification cycles:

- Route parser output was piped to `tail` or other filters.
- Exit code checks against these pipelines gave false success.
- Each required re-running the check without the pipe to diagnose the real failure.
- Cost several wasted review rounds.

## Safe Pattern

```bash
# Approach 1: avoid the pipe
check-route.sh > /tmp/out.txt
if [ $? -ne 0 ]; then ...

# Approach 2: use pipefail (bash)
set -o pipefail
check-route.sh | tail
code=$?
set +o pipefail

# Approach 3: use PIPESTATUS array (bash)
check-route.sh | tail
if [ ${PIPESTATUS[0]} -ne 0 ]; then ...
```

## Implementation Notes

- In scripts, consider `set -o pipefail` at the top to make all pipelines fail-closed.
- When debugging a pipeline, isolate each segment by running it separately.
- Document in code comments if a pipe's early exit is intentional (rare).

Related: [[memory/daily/2026-09-03]] (close-out note for this run)
