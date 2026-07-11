# Running sefi-agents on OpenCode

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`. This
file only names the OpenCode-specific wiring.

## 1. Connect OpenCode Zen
Point OpenCode at the Zen provider and select a model:
- Base URL: `https://opencode.ai/zen/v1`
- Model: `deepseek-v4-flash-free` (free window) or `deepseek-v4-flash` (paid fallback)

## 2. Skills, agents, commands
OpenCode reads `AGENTS.md` as its instructions file (the Claude Code `CLAUDE.md` analog).
Sync the skills directory into OpenCode's rules/skills path; the roster maps to OpenCode
subagent runs.

## 3. Headless (CI loops)
Invoke non-interactively with `opencode run`, piping the prompt via stdin.

## 4. Hook-event map
The SessionStart memory injection maps to OpenCode's `session.created`; a PreToolUse gate
maps to `tool.execute.before`; a Stop hook maps to `session.idle`. Full table:
`skills/sefi-orchestration/references/harness-actions.md`.
