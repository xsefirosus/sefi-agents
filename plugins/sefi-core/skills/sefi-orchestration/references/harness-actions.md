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

Platform constraint (Claude Code, live-verified 2026-08-20): a dispatched subagent has no
`Agent`/`Task` tool -- a tool absent from a subagent's tool set is never granted even if
listed in `tools` -- so it cannot itself dispatch. The `engineering-manager` role therefore
belongs to the top-level session, not a dispatched subagent, on this harness. OpenCode's
counterpart already covers this: `install-opencode.sh` writes `mode: primary` for
`engineering-manager` and `mode: subagent` for the other 13 (`adapters/OPENCODE.md`), so
OpenCode's EM keeps real top-level authority. Hermes and Codex: UNKNOWN -- not yet confirmed
against `adapters/HERMES.md` / `adapters/CODEX.md`, per this file's own rule above.

## Tool-name map
| Abstract | Claude Code | Gemini-style |
|---|---|---|
| Read | Read | read_file |
| Search | Grep | search_file_content |
| Shell | Bash | run_shell_command |
| Write | Write | write_file |

## Hook-event map
| Event | Claude Code | OpenCode | Hermes | Codex |
|---|---|---|---|---|
| Before a tool runs | PreToolUse | tool.execute.before | UNKNOWN | UNKNOWN |
| After a tool runs | PostToolUse | UNKNOWN | UNKNOWN | UNKNOWN |
| Session goes idle | Stop | session.idle | UNKNOWN | UNKNOWN |
| Session starts | SessionStart | session.created | UNKNOWN | UNKNOWN |

UNKNOWN cells are not yet documented in that harness's own adapter file
(`adapters/HERMES.md`, `adapters/CODEX.md`) -- fill in only once confirmed there, never
by porting another harness's event name as a guess.

## Reserved fields per harness (do not reuse for custom semantics)
Every harness reserves certain field/parameter names for its own protocol. Collisions
silently fail (the harness coerces to its default value) -- detect them by reading the
harness's logs or gateway responses, not by testing. Never reuse these names for custom
semantics in dispatch payloads or agent frontmatter.

| Reserved field | Harness | Meaning | Do not reuse for |
|---|---|---|---|
| `role` | Hermes | agent hierarchy ("orchestrator" / "leaf") | specialist type or job role (use `specialist_role` instead) |
| `tasks` | Hermes | dispatch payload array | anything else (only valid key for batch dispatch) |
| `background` | Hermes | async execution flag | anything else |
| `model` | Claude Code, OpenCode, Codex | model name / tier override | application-level model selection |
| `tools` | Claude Code, OpenCode, Codex | agent tool whitelist (frontmatter) | anything else (reserved for harness-level tool allowlist) |
| `disallowedTools` | Claude Code, OpenCode, Codex | agent tool blacklist (frontmatter) | anything else (reserved for harness-level safety gate) |

If a dispatch fails silently or a tool is unexpectedly unavailable, check this table first.
OpenCode's and Codex's own reserved-field sets beyond `model`/`tools` are UNKNOWN --
confirm against their adapter docs before assuming more overlap than the table states.

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

## Requested vs observed route (post-dispatch route-evidence assertion)

After a dispatch, `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh <harness> <tier>
<session-record-placeholder>` resolves the model + reasoning effort the tier map asked
for (through `${CLAUDE_PLUGIN_ROOT}/scripts/model-for.sh` -> `config/model-map.yml`, the
single resolver), gates that pair against a strict allowlist, and reports one of two
verdicts. This is the one place that per-harness mapping lives; adapters point here.

**This version reads NO session record for any harness.** An earlier revision shipped a
rollout parser here; it was stripped because no harness has a confirmed rollout format in
this repo and every parser variant tried had a fail-open shape (a decoy record could make
a downgraded run report `match`). The third argument is an accepted-but-never-opened
placeholder. The parser returns only in a future revision that has a real, documented
format.

Five states are the documented vocabulary. This version emits only the last two:
- `match` -- observed model AND effort equal the requested route. **Reserved: not emitted
  by this version.**
- `mismatch` -- a real requested route, but the record shows a different one; the
  orchestrator STOPS and reports to `inbox/` rather than accepting a downgraded run.
  **Reserved: not emitted by this version.** If a future revision ever returns it, that
  STOP-and-park rule applies.
- `invalid` -- a session record is present but off its documented schema; fail noisily, a
  field is never guessed. **Reserved: not emitted by this version.**
- `unavailable` -- the harness exposes no route readback this repo can trust. The result
  for EVERY harness whose tier resolves to a real (non-`flexible`) model today.
- `not-applicable` -- the requested tier resolves to the `flexible` sentinel
  (`config/model-map.yml:87-89` opencode, `:106-108` hermes): there is no requested
  model id, so a comparison is undefined. Without this state a naive comparator would
  false-alarm on every OpenCode/Hermes dispatch.

Exit code: 0 only on `not-applicable`; non-zero on `unavailable`; exit 2 (no JSON) on a
usage error.

| Harness | Where an observed route would live (future) | State today | Why |
|---|---|---|---|
| Claude Code | nothing -- the CLI reports no per-agent model or token usage (see the Headless invocation note above: "The CLI reports no token usage") | `unavailable` (reason `harness-exposes-no-route-readback`) | no route readback exists on this harness, by design |
| Codex | the session rollout `rollout-*-<thread-id>.jsonl` under `${CODEX_HOME:-~/.codex}/sessions` (technique adapted from astral-orchestrator `check-primary.py` lines 82-101, MIT: match rollout *filenames* only, never read rollout contents) | `unavailable` (reason `codex-rollout-format-unconfirmed`) | `CODEX_THREAD_ID`, that sessions directory, and the rollout JSON shape are NOT documented in `adapters/CODEX.md` or `.codex/config.toml`. Per this file's gap rule (lines 44-47) the cell stays UNKNOWN and `check-route.sh` opens nothing; a real parser returns only once `adapters/CODEX.md` documents the format. |
| OpenCode | a session record -- location and format | `not-applicable` | `adapters/OPENCODE.md` documents no session-record location/format, so that cell stays UNKNOWN; and every OpenCode tier resolves to `flexible` (`config/model-map.yml:87-89`), so `check-route.sh` short-circuits to `not-applicable` regardless. |
| Hermes | the OpenAI-compatible `usage` block carries tokens (Headless invocation note above), but not a model readback | `not-applicable` (`unavailable` if a tier is ever pinned to a real id) | model readback is UNKNOWN in `adapters/HERMES.md`; and every Hermes tier resolves to `flexible` (`config/model-map.yml:106-108`), so `check-route.sh` returns `not-applicable` today. |

Honest net result: Phase 3 ships with NO live route comparison on any of the four
harnesses. Every call returns `unavailable` or `not-applicable`. `match` / `mismatch` /
`invalid` are reserved for a future revision with a confirmed rollout format and a real
JSON parser -- Codex is the first candidate. This is the expected outcome, not a defect:
the documented five-state vocabulary and the honest `unavailable` / `not-applicable`
verdicts are the deliverable.
