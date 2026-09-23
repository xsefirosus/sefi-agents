---
description: Search private local Memory Journalist notes, optionally in one explicitly named project.
argument-hint: "<query> [--project <slug>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/memory-search.sh:*)
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/memory-search.sh <query> [--project <slug>]` from the
project root. Without `--project`, search only this project's local Markdown notes. A
cross-project lookup requires both a named project and an enabled local cross-project
setting. Never perform an ambient scan.
Count first (count or files_with_matches) before reading full files; open full notes only for hits that matter.
