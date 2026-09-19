---
description: Rebuild or check the disposable local Memory Journalist search index.
argument-hint: "rebuild|status"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/memory-index.sh:*)
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/memory-index.sh <rebuild|status>` from the project
root. Rebuilding reads Markdown notes and writes only disposable index data; it never
modifies a session note.
