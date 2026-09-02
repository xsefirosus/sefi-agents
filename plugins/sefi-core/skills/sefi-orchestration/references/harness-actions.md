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
<session-record-or-thread-id>` resolves the model + reasoning effort the tier map asked
for (through `${CLAUDE_PLUGIN_ROOT}/scripts/model-for.sh` -> `config/model-map.yml`, the
single resolver), gates that pair against a strict allowlist, and reports one of the six
states below. This is the one place that per-harness mapping lives; adapters point here.
`check-route.sh` is a thin interpreter-resolving shim over `check-route.py`, a stdlib
Python 3.11+ parser (real `json.loads` per rollout line, top-level dict access only).

**`match` / `mismatch` / `invalid` are LIVE for Codex, reserved for the other three.**
For a Codex dispatch the third argument is the `CODEX_THREAD_ID` (a lowercase UUID) or `-`
when none is available; the parser reads the last top-level `turn_context` record's
`model` / `effort` from
`rollout-*-<thread-id>.jsonl` under `${CODEX_HOME:-~/.codex}/sessions` and compares. It
reads rollout *filenames* and those two fields only -- never rollout free text. An earlier
POSIX-sh revision was reduced for five fail-open shapes (a decoy record could make a
downgraded run report `match`); `json.loads` + top-level-only dict access structurally
cannot have them. claude-code exposes no per-agent route readback; opencode / hermes
resolve every tier to `flexible` -- those are limitations of those harnesses, not of the
check, and their cells stay `unavailable` / `not-applicable`.

The check is tamper-EVIDENT against an accidental route downgrade (the harness silently
running a different model/effort than the tier map asked for), not tamper-PROOF: an actor
who controls the dispatch environment (`CODEX_HOME`, `PATH`) can still point it at a forged
rollout -- that is the same trust level as the harness itself.

Six states are the documented vocabulary:
- `match` -- observed model AND effort equal the requested route. **LIVE for Codex.**
  Exit 0.
- `mismatch` -- a real requested route, but the rollout shows a different one; the
  orchestrator STOPS and reports to `inbox/` rather than accepting a downgraded run.
  **LIVE for Codex** (reserved for the other three). Exit non-zero.
- `invalid` -- a session rollout is present but off its documented schema (not JSON, no
  `turn_context`, a malformed last `turn_context`, an ambiguous thread id); fail noisily,
  a field is never guessed. **LIVE for Codex** (reserved for the other three). Exit
  non-zero.
- `unavailable` -- the harness exposes no route readback this repo can trust (claude-code
  always; Codex when no thread id / no rollout is available).
- `not-applicable` -- the requested tier resolves to the `flexible` sentinel
  (`config/model-map.yml:87-89` opencode, `:106-108` hermes): there is no requested
  model id, so a comparison is undefined. Without this state a naive comparator would
  false-alarm on every OpenCode/Hermes dispatch.
- `skipped` -- `check-route.sh` exited 3: no `python3` / `python` 3.11+ interpreter is
  available, so the check never ran. Record `route` as `skipped` and move on -- it is
  **not** a `mismatch` and does **not** block or STOP the dispatch. The only "the check
  could not run" state.

Exit code: 0 only on `match` or `not-applicable`; non-zero on `mismatch` / `invalid` /
`unavailable`; exit 2 (no JSON) on a usage error; exit 3 (shim, stderr notice) when no
`python3` / `python` 3.11+ interpreter is available -- the orchestrator records `route`
as `skipped` and treats it as "the check did not run" (never as `mismatch`).

| Harness | Where the observed route lives | State today | Why |
|---|---|---|---|
| Claude Code | nothing -- the CLI reports no per-agent model or token usage (see the Headless invocation note above: "The CLI reports no token usage") | `unavailable` (reason `harness-exposes-no-route-readback`) | no route readback exists on this harness, by design |
| Codex | the session rollout `rollout-*-<thread-id>.jsonl` under `${CODEX_HOME:-~/.codex}/sessions`, format documented in `adapters/CODEX.md` `## Session rollout` (technique adapted from astral-orchestrator `check-primary.py:82-101`, MIT: match rollout *filenames* only, read only `model` / `effort` from the last top-level `turn_context`, never rollout free text) | **LIVE: `match` / `mismatch` / `invalid`** per the state of the run (`unavailable` when no `CODEX_THREAD_ID` / rollout is available) | `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh` (the `check-route.py` parser) reads the rollout and compares observed model + effort against the tier map. Fields not confirmable from the two cited MIT sources are marked UNKNOWN in `adapters/CODEX.md`; an off-schema rollout is `invalid`, never a guessed `match`. |
| OpenCode | a session record -- location and format | `not-applicable` | `adapters/OPENCODE.md` documents no session-record location/format, so that cell stays UNKNOWN; and every OpenCode tier resolves to `flexible` (`config/model-map.yml:87-89`), so `check-route.sh` short-circuits to `not-applicable` regardless. A limitation of the harness, not of the check. |
| Hermes | the OpenAI-compatible `usage` block carries tokens (Headless invocation note above), but not a model readback | `not-applicable` (`unavailable` if a tier is ever pinned to a real id) | model readback is UNKNOWN in `adapters/HERMES.md`; and every Hermes tier resolves to `flexible` (`config/model-map.yml:106-108`), so `check-route.sh` returns `not-applicable` today. A limitation of the harness, not of the check. |

Net result: live requested-vs-observed route comparison now exists on **Codex** -- a real
`json.loads` parser over the session rollout, `match` / `mismatch` / `invalid` per the
state of the run. claude-code stays `unavailable` and opencode / hermes stay
`not-applicable` by those harnesses' own limits (no route readback; every tier resolves to
`flexible`), not by any limitation of the check. `match` / `mismatch` / `invalid` remain
reserved for those three until their adapter docs document a readable route.
