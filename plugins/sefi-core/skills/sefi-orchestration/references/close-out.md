# close_out -- the canonical session-journal behavior

`close_out` is one of the five agentic signals every loop declares. It closes a
substantial work session with either one privacy-filtered Memory Journalist note or an
explicit SKIP. It is not a transcript recorder.

## When it fires

Run close_out after persistence and before a loop reschedules, or when a distinct
interactive work session is finished. `/sefi:close-session` is the explicit close action.
The next session start also recovers an unfinished buffer.

All substantial work in one session is grouped into one note. Separate work sessions
produce separate notes. Do not run it for greetings, casual chats, status checks, or
simple factual replies.

## What counts as durable

Nominate a factual observation only when it would help a later session act correctly:

- a result, decision, constraint, failed approach, or unresolved blocker
- a material file change and the reason it matters
- a correction to a previously recorded fact
- an observed route mismatch or repeated validation failure that requires follow-up

Do not nominate raw conversations, hidden reasoning, secret values, command output,
command dumps, full diffs, or task receipts. Use `state/` for review artifacts and
`.sefi/runs/` for content-free task receipts.

## How it writes

The orchestrator dispatches the **Memory Journalist**. Other agents only submit factual
nominations. The Memory Journalist is the sole writer for `memory/`.

1. Privacy-filter each nomination before it enters `.sefi/journal/<session-id>/`.
2. Use a per-session lock, monotonic cursor, temporary file, flush, and atomic rename.
3. At close, build exactly one note at
   `memory/sessions/YYYY/MM/YYYY-MM-DD-HHmm-two-or-three-word-title.md`.
4. Include the fixed v0.8 frontmatter and sections. Missing facts read `None` or
   `Not applicable`.
5. Regenerate the memory router after the note is durable. Retain the buffer until both
   writes succeed. Repeated close calls must be idempotent.
6. Mirror a filtered copy only when cross-project memory is explicitly enabled on a
   positively identified persistent local machine. Skip CI, containers, cloud, and
   unknown environments.

## When nothing is durable

Record `SKIP` with a reason and write no note. An empty note creates misleading retrieval
evidence.

## Failure is not silent

If a buffer or final note cannot be written, report the error and retain the buffer for
recovery at the next session start. Never silently discard a factual nomination.

Self-test: a session produces one privacy-filtered note, a recoverable buffer after a
failure, or SKIP with a reason. Never neither.
