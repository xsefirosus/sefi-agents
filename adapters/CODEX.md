# Running sefi-agents on Codex

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`.

## 1. Unlock subagents
Set `multi_agent = true` in the Codex config. Without it, Codex has no subagent tool and
the roster runs sequentially in one context -- state that explicitly rather than pretending
parallelism exists.

## 2. Roster and instructions
Codex reads `AGENTS.md` as its instructions file. Map the roster into Codex's agent config;
`model:` and `disallowedTools:` are advisory on Codex, so the gates are the hard line.

## 3. Scheduling
Loop triggers map to Codex automations.

## 4. Worktrees
Codex may create its own sandbox worktree for isolation. The worktree procedure in
`docs/LOOPS.md` is provenance-gated: it only removes worktrees under `.worktrees/` or
`worktrees/`, so it leaves a Codex-created sandbox worktree alone.

## 5. Headless (CI loops)
Invoke non-interactively with `codex exec`.
