# Harness Actions -- the narrow cross-runtime map

Skills and agents describe abstract actions; this table maps only the genuinely ambiguous
ones to each runtime. Where a harness has no native equivalent, the fallback is stated.
Everything not listed here is identical enough across runtimes to need no mapping. This is
the one place the harness mapping lives; adapters point here and never duplicate it.

## Ambiguous actions
| Abstract action | Claude Code | Hermes | OpenCode | Codex |
|---|---|---|---|---|
| Dispatch a subagent | Task / subagent | `delegate_task(...)` (prompt-instructed) | subagent run | needs `multi_agent = true`; else sequential |
| Task tracking | TodoWrite | agent state | task list | agent config |
| Your instructions file | CLAUDE.md | MEMORY.md | AGENTS.md | AGENTS.md |
| Attach a rule for matching files | hook / skill | skill | rule | config |
| Invoke the harness headless | see row below | HTTP gateway | `opencode run` | `codex exec` |

Fallback: a harness with no subagent tool executes the roster sequentially in one context;
state that explicitly rather than pretending parallelism exists.

## Tool-name map
| Abstract | Claude Code | Gemini-style |
|---|---|---|
| Read | Read | read_file |
| Search | Grep | search_file_content |
| Shell | Bash | run_shell_command |
| Write | Write | write_file |

## Hook-event map
| Event | Claude Code | OpenCode |
|---|---|---|
| Before a tool runs | PreToolUse | tool.execute.before |
| Session goes idle | Stop | session.idle |
| Session starts | SessionStart | session.created |

## Headless invocation (how a loop or CI job calls each harness non-interactively)
- Claude Code (live-verified): `claude --print --dangerously-skip-permissions --add-dir
  <project_root>`, with `cwd` pinned to the project, the prompt piped via stdin (Windows
  CLI argument-length limits break long inline prompts), UTF-8 decode with replacement for
  invalid bytes (a real Unicode crash otherwise), a per-call timeout, and detection of the
  plain-text "session limit" notice (non-retryable; park the item in `inbox/` and stop).
  The CLI reports no token usage; estimate chars/4 if a number is needed.
- OpenCode: `opencode run`.
- Codex: `codex exec`.
- Hermes: HTTP to its local gateway; its OpenAI-compatible responses carry a real `usage`
  block -- record it.
