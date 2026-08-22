#!/usr/bin/env bash
# inject-orchestrator-role.sh -- SessionStart hook. Prints the orchestrator directive for
# the top-level session only. Guarded exactly like inject-memory.sh: silent (exit 0, no
# output) in any project that is not sefi-scaffolded, so an unrelated repo is never told it
# is running this chain. Read-side only: prints and exits, never writes.
#
# Why this hook exists at all, not just prose in an agent file: a dispatched Claude Code
# subagent has no `Agent`/`Task` tool -- a tool absent from a subagent's tool set is never
# granted even if listed in `tools` -- so it structurally cannot dispatch further subagents.
# Only the top-level session can drive the product-manager -> software-engineer -> qa-
# engineer chain. `SessionStart` fires once for the top-level session and never for a
# dispatched subagent, so this is the one mechanically-scoped place to say so.
#
# The trailing close_out line closes a related gap the same way: Claude Code's Stop hook
# was considered and rejected for this -- its stdout is invisible to the model on a plain
# exit 0 (verified against official docs), and forcing a reminder to actually reach the
# model requires exiting 2 or returning a "reengage" decision, which interrupts every
# session (however trivial) to force one more turn. That cost is not worth paying for a
# nudge. This SessionStart line is free -- it rides in the same injection that already
# fires -- so the close_out reminder lands here instead, at the START of the session, not
# the end. It is still advisory prose, same honest limit as the rest of this file: nothing
# stops the top-level thread from ignoring it.
set -euo pipefail

CONFIG="config/sefi.config.yml"
[ -f "$CONFIG" ] || exit 0

cat <<'EOF'
SEFI ORCHESTRATOR ROLE: this project runs the sefi-agents chain. Claude Code subagents
cannot dispatch subagents, so this top-level thread is the only place the chain can be
driven from. Before acting: invoke the sefi-core:sefi-orchestration skill and resolve the
request against its routing table. Dispatch specialists via the Agent tool. Never write the
implementation yourself -- route edits through a dispatched software-engineer, which keeps
its own worktree isolation and tool restrictions. Before ending, if worth remembering, dispatch knowledge-manager (close_out).
EOF
