---
description: Control the optional local-only cross-project memory mirror.
argument-hint: "enable|disable|status"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/memory-cross-memory.sh:*)
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/memory-cross-memory.sh <enable|disable|status>` from a
project root. Cross-project memory is optional and off by default. Enable only after the
user has chosen it for this project. It mirrors only filtered notes on a positively
identified persistent local machine and skips CI, containers, cloud, unknown hosts,
credential-bearing remotes, symlinks, and unsafe paths.
