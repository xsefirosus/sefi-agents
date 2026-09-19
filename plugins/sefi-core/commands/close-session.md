---
description: Close the current substantial work session into one private, structured Memory Journalist note.
argument-hint: "[--status completed|partial|blocked]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/memory-journal.sh:*)
---

Close the current Sefi work session. First ensure factual nominations have been filtered
and buffered under `.sefi/journal/<session-id>/`. Then run:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/memory-journal.sh close
```

Report the final note path, `SKIP` reason, or recoverable failure. The command is
idempotent. Do not create a note for greetings, casual chats, status checks, or a simple
factual reply. Never include raw conversation, reasoning, secret values, command dumps,
or full diffs.
