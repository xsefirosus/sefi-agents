---
name: memory-protocol
description: Use when nominating, closing, recovering, searching, or indexing Sefi's local-first Memory Journalist notes.
managed-by: sefi-agents
---

# Memory protocol

Runtime memory is private to the current project. It lives under `memory/`, is ignored by
Git, and is never packaged. Markdown notes are the source of truth; router files, indexes,
and caches are disposable and must be rebuilt from Markdown. Do not put runtime notes in a
public repository, an issue, a release, or a prompt.

User instructions always override this skill. All factual output follows the
anti-hallucination skill: cite or mark UNKNOWN, never guess.

## When to use it

Use the protocol only for substantial work: an implemented result, a decision, a material
constraint, a failure that needs follow-up, or a correction. Skip greetings, casual chats,
status checks, simple factual answers, raw transcripts, hidden reasoning, commands,
command output, full diffs, and secret values.

## Session journal

The Memory Journalist is the sole `memory/` writer. Other agents nominate factual content
under `.sefi/journal/<session-id>/`; the journal uses per-session locks, monotonic cursors,
temporary files, flushes, and atomic renames.

One substantial work session creates one note when closed. Separate sessions create
separate notes. An unavailable harness session identity falls back to a generated UUID and
UTC start time in ignored `.sefi/current-session`. `/sefi:close-session` is idempotent.
At the next session start, unfinished buffers are recovered before new work begins.

Use the managed helper from the project root:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/memory-journal.sh nominate --kind substantive ...
${CLAUDE_PLUGIN_ROOT}/scripts/memory-journal.sh close
```

The final path is:

```text
memory/sessions/YYYY/MM/YYYY-MM-DD-HHmm-two-or-three-word-title.md
```

The title uses two or three factual lower-case kebab-case words. Required frontmatter is
`title`, `created-at`, `project`, `session-id`, `status`, `keywords`,
`related-projects`, `related-notes`, and `managed-by: sefi-agents`. Status is
`completed`, `partial`, or `blocked`.

Every note has these sections, in order: Context Summary, Result, Useful Information, Why
This Happened, Files Modified, Benefits, Tradeoffs and Limits, and Follow-up. When a fact
does not exist, write `None` or `Not applicable`.

## Privacy filter

Filter each nomination before buffering and before finalization. Strip credential-bearing
URLs, key or token assignments, known key shapes, `<private>...</private>` blocks, shell and
PowerShell prompt lines, and diff blocks. If uncertain whether a detail is private, omit
it and state the consequence generically. Do not log what was removed.

## Local search and index

`/sefi:memory-search <query>` searches local Markdown notes plus ignored-local
`audits/` reports (local queries only -- audit reports never enter the cross-project
mirror). Search ranking is exact title
and keyword matches, then project and related-note matches, then note-body matches, with
the newest note as the final tie-breaker. `/sefi:memory-index rebuild` reconstructs the
complete disposable index from Markdown without modifying notes; `status` reports whether
source hashes and cursors are fresh.

## Optional cross-project memory

Cross-project memory is disabled by default. `/sefi:init` explains the option and asks
only in an interactive project initialization; unattended initialization keeps it off.
`/sefi:cross-memory enable|disable|status` changes the local project setting.

When explicitly enabled, a filtered note may be mirrored under
`~/sefi-memory/<project-slug>/`. Use a credential-free Git owner/repository slug, or a
sanitized local-path fallback. Never mirror or search across projects from CI, containers,
cloud hosts, unknown machines, unsafe paths, symlinks, credential-bearing remotes, or an
unnamed-project request. Read another project only when the user names it or the current
task clearly connects to recorded project metadata; no ambient bulk scans.

## Failure behavior

Retain the source buffer until the final note and memory router are durable. If either
write fails, report the failure without private content and recover the buffer at the next
session start. Do not manually edit generated router or index data.
