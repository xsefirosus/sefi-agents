## Objective
Make the top-level Claude Code session reliably drive the sefi-agents chain itself
(`product-manager` -> `software-engineer` -> `qa-engineer`), because a dispatched
`engineering-manager` subagent structurally cannot. Confirmed against official Claude Code
docs, not assumed: the `Agent`/`Task` tool is outside the tool set available to subagents,
and "a tool that isn't available to subagents is never granted, even when listed in
`tools`" (code.claude.com/docs/en/tools-reference.md, "Agent tool behavior"). Adding `Task`
to `engineering-manager.md`'s frontmatter would therefore change nothing. Live-reproduced
2026-08-20 on this repo's own `main`: a dispatched `engineering-manager` resolved the
routing table correctly, then returned BLOCKED with zero artifacts because it had no
dispatch mechanism -- it correctly refused to fake the chain by writing files via `Bash`,
citing `human-checkpoint.md`'s own record of that exact failure.

Deliver the role instruction through a second `SessionStart` hook, which is mechanically
scoped to the top-level session and never reaches a dispatched subagent.

OpenCode needs no part of this: `install-opencode.sh` already writes `mode: primary` for
`engineering-manager` and `mode: subagent` for the other 13 (adapters/OPENCODE.md), so that
harness already grants the EM real top-level authority. This plan does not touch it.

Also folds in a prerequisite bug fix: on Windows, the hook command string breaks before any
of this can run (step 1).

### Approaches weighed (the rejected one is documented on purpose)
- **Approach A -- SessionStart hook injection (CHOSEN).** Mechanically scoped: live-verified
  2026-08-20 that `SessionStart` fires exactly once for the top-level session and never for
  a dispatched subagent (a hook appending one line per firing produced exactly one line,
  while a real subagent ran mid-session and observed the log file already present). Cost: a
  small per-session context charge, and one more moving part in `hooks.json`. Matches this
  repo's existing preference for a mechanical check over prose discipline
  (`check-handoff.sh`, `check-citation.sh`, `scan-placeholders.sh`).
- **Approach B -- an instruction in the project's `CLAUDE.md` (REJECTED).** Simpler and
  needs no new script, but not scopable: official docs state each subagent receives
  "CLAUDE.md files (project rules, globals)" (code.claude.com/docs/en/sub-agents.md), so
  the orchestrator instruction reaches every dispatched specialist too. It can be softened
  with conditional phrasing ("when you are directly handling a fresh human request..."),
  and one live test of that phrasing showed no contamination in a dispatched
  `research-analyst` -- but that is the model correctly judging a trigger condition every
  time, not a guarantee, and a single clean run is not proof. Rejected in favor of a
  mechanism that cannot reach a subagent at all. Also invasive: it would require
  `/sefi:init` to create or edit a file this plugin does not own.

## Steps
- [ ] 1. Quote the placeholder in both `hooks/hooks.json` command strings. (needs: -)
  Each becomes `"\"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh\""` (embedded literal quotes)
  instead of bare. Prerequisite, not a nice-to-have: live-reproduced 2026-08-20 on a Windows
  profile path containing a space, where the harness substitutes the resolved path into the
  command string unquoted and the shell then splits it -- `bash: C:/Users/<first-word>: No
  such file or directory`, exit 127, surfaced as a non-blocking hook error, meaning
  `check-bash-write.sh`'s `disallowedTools` enforcement was silently inert for that session.
  Verified by hand: the same resolved path wrapped in literal double quotes runs clean
  (exit 0). Without this step the new hook in step 3 fails identically on such a machine.
  `install.sh`'s `sed "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g"` resolution (install.sh:121) passes
  the added quotes through untouched, so the fallback install path gets the same fix for
  free -- confirm that rather than assume it.
- [ ] 2. Write `plugins/sefi-core/scripts/inject-orchestrator-role.sh`. (needs: -)
  A `SessionStart` hook that prints the orchestrator directive to stdout. Guard first,
  exactly as `inject-memory.sh` guards on a missing vault index --
  `[ -f config/sefi.config.yml ] || exit 0` -- so it stays silent in any project that is not
  sefi-scaffolded (an unrelated repo must never be told it is running this chain). Read-side
  only: it prints and exits, never writes. Keep the directive under 600 characters; it is
  charged to every session in a sefi project, and `inject-memory.sh` already spends up to
  `memory.inject_char_cap` (default 1500) of the same budget. Content, in substance: this
  project runs the sefi-agents chain; Claude Code subagents cannot dispatch subagents, so
  this top-level thread is the only place the chain can be driven from; invoke the
  `sefi-core:sefi-orchestration` skill and resolve the request against its routing table
  before acting; dispatch specialists via the `Agent` tool; never write the implementation
  yourself -- route edits through a dispatched `software-engineer`, which keeps its own
  worktree isolation and tool restrictions.
- [ ] 3. Add the new script as a SECOND `SessionStart` entry in `hooks.json`. (needs: 1, 2)
  Alongside `inject-memory.sh`, not replacing it, carrying the same quoting from step 1.
  Keep it `SessionStart` specifically: `test-scripts.sh:589` asserts `hooks.json` declares
  no `Stop`/`SessionEnd`/`PostToolUse` hook, because a write-side hook cannot run the
  memory-protocol privacy filter -- this hook is read-side and must not break that
  assertion. `install.sh`'s `wire_claude_settings()` merges `.hooks` wholesale
  (install.sh:126-141), so the fallback claude target picks the new entry up with no
  installer change; verify that against a real temp `$HOME` rather than assuming it.
- [ ] 4. Add at least 6 regression assertions to `scripts/ci/test-scripts.sh`. (needs: 3)
  (a) every command string in `hooks.json` is quote-wrapped -- the step-1 fix, asserted so
  it cannot silently regress; (b) a resolved command whose path contains a space executes
  cleanly, proving the fix against the actual failure shape rather than the quoting
  cosmetics; (c) `inject-orchestrator-role.sh` prints nothing and exits 0 when
  `config/sefi.config.yml` is absent; (d) it prints the directive when that file is present;
  (e) its output stays within the 600-character cap; (f) after `install.sh --target claude`
  against a temp `$HOME`, `settings.json`'s `SessionStart` array carries BOTH hooks and the
  pre-existing `inject-memory.sh` entry survives the merge.
- [ ] 5. Record the platform constraint in `references/harness-actions.md`. (needs: 3)
  Add a row, or a stated note under the existing "Dispatch a subagent" row, saying that on
  Claude Code a dispatched subagent cannot itself dispatch -- so the EM role belongs to the
  top-level session -- with the same fact's OpenCode counterpart (`mode: primary`) named,
  and Hermes/Codex left UNKNOWN per that file's own rule. Update `engineering-manager.md`
  only if it fits inside the agents' word budget (`validate-token-budget.sh`); if it does
  not, say so and leave the agent file alone rather than trading away a Protocol line.
- [ ] 6. Docs and release: CHANGELOG, README row, version bump to 0.3.18. (needs: 4, 5)
  CHANGELOG entry naming both the fix and the honest scope (Claude Code only; OpenCode
  already covered; Hermes/Codex unwired); a README known-limits-table row in the established
  two-column shape; version bump in `.claude-plugin/marketplace.json` (both
  `metadata.version` and the `sefi-core` plugin entry) and
  `plugins/sefi-core/.claude-plugin/plugin.json`. If README's sample CI output block quotes
  a script count, re-run the validator and take the number from real output rather than
  incrementing it by hand.
- [ ] 7. Run `bash plugins/sefi-core/scripts/ci/run-all.sh` in full. (needs: 6)
  Paste the real tail of its output into the final report, including the updated
  `test-scripts` count. A run that was not executed is PENDING, never assumed.

## Files Touched
plugins/sefi-core/hooks/hooks.json; plugins/sefi-core/scripts/inject-orchestrator-role.sh
(new); plugins/sefi-core/scripts/ci/test-scripts.sh;
plugins/sefi-core/skills/sefi-orchestration/references/harness-actions.md;
plugins/sefi-core/agents/engineering-manager.md (only if within word budget); CHANGELOG.md;
README.md; .claude-plugin/marketplace.json; plugins/sefi-core/.claude-plugin/plugin.json

## Requires Tools
bash, jq, sed, grep, awk, git

## Risks
- The injected directive is prose the top-level session must choose to honor. Unlike a
  dispatched `engineering-manager` -- whose `disallowedTools: Write, Edit, MultiEdit` is a
  hard platform wall -- the top-level thread keeps full write access throughout, so "never
  write the implementation yourself" degrades from an enforced guarantee to a strong
  instruction. This plan does not close that gap and must not claim to. The one real
  backstop that survives is that the actual edit still happens inside a dispatched
  `software-engineer` with its own worktree isolation; keep that step mandatory.
- A `SessionStart` injection can fade from context after compaction in a long session, the
  same known weakness the existing memory-router injection already has. Not a new risk
  class, but it means the chain is most reliable early in a session.
- `hooks.json` is consumed by two different paths -- Claude Code's native plugin loader and
  `install.sh`'s `jq` merge. The added quoting must be verified against BOTH, since only the
  second is reachable from CI; a fix proven only against the installer would leave the
  documented primary install path untested.
- Step 1 fixes the plugin's own command string. It does not fix the underlying harness
  behavior of substituting an unquoted path, which is upstream in Claude Code and out of
  scope here; state it as a mitigation, not a repair.
- Adding a second `SessionStart` hook doubles the per-session injection surface. If the
  combined output crowds the context budget, the cap in step 2 is the lever to tighten, not
  the memory router's.
- No prior note in `memory/decisions/` constrains this plan (vault checked; the relevant
  findings from the 2026-08-20 session are daily-note candidates, not accepted decisions).

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` exits 0 with all validators passing and a
`test-scripts` count at least 6 higher than the current 137. A fresh
`bash install.sh --target claude` against a throwaway `$HOME` produces a `settings.json`
whose `SessionStart` array contains both `inject-memory.sh` and
`inject-orchestrator-role.sh`, each with a quote-wrapped resolved command, proven by `jq`
output rather than asserted. Running `inject-orchestrator-role.sh` from a directory with no
`config/sefi.config.yml` produces empty stdout and exit 0; running it from one that has the
file produces the directive within its stated character cap.
