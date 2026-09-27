# Running sefi-agents on OpenCode

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`. This
file only names the OpenCode-specific wiring.

## 1. Connect OpenCode Zen

Point OpenCode at the Zen provider and select a model:
- Base URL: `https://opencode.ai/zen/v1`
- Model: your choice -- run `/models` in OpenCode to see what Zen currently offers, free or
  paid. Whatever you pick, the `opencode/` provider prefix is required in the value (e.g.
  `opencode/<model-id>`); OpenCode resolves a bare model id as a real provider/model
  identifier and fails (see Troubleshooting). Not naming a specific model here on purpose:
  Zen's free lineup rotates -- `deepseek-v4-flash-free` was verified real on 2026-08-11 and
  retired by 2026-08-21 -- so this repo's own agent install no longer pins one either (see
  "Model tiers and reasoning" below).

## 2. Install

OpenCode auto-discovers agents, skills, and commands under
`~/.config/opencode/{agents,skills,commands}/` (or `$OPENCODE_HOME` if set). From the
repo root:

```sh
bash plugins/sefi-core/scripts/install-opencode.sh
# or, through the human-fallback installer:
./install.sh --target opencode
```

`--force` re-installs over an existing copy. Skills and commands are copied verbatim;
their frontmatter has no field collisions with OpenCode's schema. Agents are
transformed: OpenCode's `tools` field is a strictly-typed `{name: boolean}` object (and
deprecated in favor of `permission`), so a raw copy of our `tools: Read, Grep, ...`
string fails schema validation. The script converts each agent's `tools:` /
`disallowedTools:` pair into the 15-key `permission:` mapping OpenCode expects
(conversion table lives in the script's comments). `model:` is resolved through
`config/model-map.yml`: the shipped `flexible` policy omits the field so OpenCode uses the
model you selected, while an explicit map writes the chosen provider/model id. A `mode:` field is
also written: `primary` for `sefi-agents` only, `subagent` for every other
agent, so OpenCode's own Tab-cycle switcher shows just the one entry point instead of
all 17 (see "Agent visibility" below). Every other frontmatter field and the entire body
is preserved byte-for-byte.

### Updating an existing install (`--auto-update`)

Every install writes a `sefi-package-manifest/v1` record beside the installed
`scripts/` copy: per-file hashes plus the `source_version` and `source_commit`
the copy came from. Re-running with `--auto-update` diffs that record against
the current checkout before writing anything:

- `current` -- installed hashes and version match the source. Exits 0, changes
  nothing.
- `stale` -- the source moved on (the message names the new version and
  commit). Runs the normal install below.
- `drift` -- installed files were modified by hand (the message names them).
  Stops with an error rather than overwriting; re-run with `--force` as well to
  overwrite deliberately, or reconcile by hand.

With no installed manifest on disk, `--auto-update` performs a fresh install.
Ceiling, stated plainly: version tracking covers the `scripts/` subtree only --
scripts are copied byte-for-byte, so only that subtree has a stable source
digest to check. Agents are transformed and prose has its plugin-root
placeholder resolved, so a `stale` update overwrites agents, skills, and
commands exactly like `--force` would, with no hash baseline to diff against.

Installation is user-wide. Run `/sefi:init` once from each project root before its first
routed request; the installer cannot safely auto-initialize an arbitrary repository. Init
leaves the optional local/private cross-project memory mirror off unless an interactive user
explicitly enables it.

## 3. Headless (CI loops)

Invoke non-interactively with `opencode run`, piping the prompt via stdin.

## 4. Hook-event map

The SessionStart memory injection maps to OpenCode's `session.created`; a PreToolUse gate
maps to `tool.execute.before`; a Stop hook maps to `session.idle`. Full table:
`skills/sefi-orchestration/references/harness-actions.md`.

That is the mapping, not an installer: `install-opencode.sh` copies agents, skills, and
commands, and no sefi installer creates hooks outside the Claude Code plugin path. To get
the memory injection here, wire `scripts/inject-memory.sh` to `session.created` yourself.
Skipping it costs an optimization, not correctness -- the memory-protocol READ ladder still
retrieves vault content on demand.

`session.created` is a session-start event, not a first-routed-request event. It may carry
ordinary session-start context, but it cannot implement a one-time route reminder without
inventing unsupported hook state. The successful install message supplies the documented
reminder to run `/sefi:init` before the first routed request.

When you wire `session.created`, also have it print a one-line reminder: before ending,
if this session found something worth remembering, route a factual nomination to `memory-journalist` (the
`close_out` behavior, `skills/sefi-orchestration/references/close-out.md`) rather than
letting the session end without saving anything. Matches the same line Claude Code's
`inject-orchestrator-role.sh` injects at session start.

The optional cross-project memory mirror needs none of this wiring --
`memory-cross-memory.sh` is plain bash the Memory Journalist runs directly at close_out,
so it works identically here.
One real caveat, not OpenCode-specific: a sandbox that disallows writes outside the project
directory makes the mirror fail closed by design, same as a detected ephemeral environment
-- the project-local vault write is never affected either way.

**Why not `session.idle` (the closer analog to "remind right as the session ends"):**
checked and rejected, not just skipped. `session.idle` is not a shell-command hook like
the rest of this table -- it requires an actual OpenCode plugin (TypeScript/JavaScript),
which this project has never needed and does not want to start requiring (the whole
pitch is markdown plus POSIX shell, zero runtime deps). It also fires only after the
agent loop has already ended (live-confirmed via OpenCode's own issue tracker,
2026), so by the time it runs there is no turn left to inject a reminder into anyway. A
`session.created` reminder is the honest, buildable equivalent -- a nudge at the start,
same limitation as Claude Code's version: advisory only, nothing enforces it.

## Troubleshooting

OpenCode does not have a single all-in-one `doctor` command (the way Hermes has
`hermes doctor --fix` or Codex has `codex doctor`). For general config/paths diagnostics
use:

- `opencode debug paths` -- shows the real config / data / cache directories on the
  current machine.
- `opencode debug config` -- shows the fully resolved, merged config.

For an agent that fails to load with `Configuration is invalid`, `opencode debug agent
<name>` shows the parse error. If the error points at a `tools: <string>` field, the
installed copy under `~/.config/opencode/agents/` still has the raw string -- re-run
`install-opencode.sh --force` to regenerate it.

**`Model not found: <provider/model-id>`** on any subagent dispatch -- the installed
agent was generated from an explicit map that names a model OpenCode cannot resolve.
Fix the value in `config/model-map.yml` (the provider prefix is required), then re-run
`install-opencode.sh --force`. To return to the user-selected session model, restore the
shipped `flexible` value. A dispatch must surface this failure rather than silently
degrading to an unconstrained generic agent.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI secrets. See
`Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

`install-opencode.sh` resolves each agent's harness-neutral `tier:` through
`plugins/sefi-core/config/model-map.yml`. The shipped map's `opencode:`
block maps every tier to the sentinel `flexible`, not a concrete model id:

| Tier | Model | reasoningEffort |
|---|---|---|
| high | `flexible` | (none written) |
| mid | `flexible` | (none written) |
| low | `flexible` | (none written) |

**Why not a pinned free model.** `deepseek-v4-flash-free` was web-verified real on Zen on
2026-08-11 and confirmed retired from Zen entirely by 2026-08-21 -- ten days later. OpenCode
Zen's free lineup rotates (observed cycling through Big Pickle, MiniMax M2.5 Free, Mimo V2
Pro/Omni Free, Nemotron 3 Super/Ultra Free, North Mini Code, and others); hardcoding
whatever happens to be free this week just means this repo breaks again on the next
rotation, exactly as it just did. `flexible` means: `install-opencode.sh` writes no
`model:` line and no `options.reasoningEffort` block at all, for that tier. Every converted
agent then falls back to whatever model YOU have configured directly in OpenCode (section 1
above -- run `/models` in OpenCode to see what Zen currently offers, free or paid, and pick
one). sefi-agents' orchestration does not depend on which model that is.

**Cost, stated plainly:** with every tier `flexible`, all agents inherit the one model you
picked, so the qa-engineer judges the software-engineer on the identical model --
generator/evaluator separation collapses to instructions-only. That is not a new cost this
change introduces: the previous pinned-to-one-free-model setup paid the exact same price,
just silently. To restore a real adversary, edit `config/model-map.yml`'s `opencode:` block
yourself and name two different real identifiers on `high` and `mid` (the `opencode/`
provider prefix is required on any real value you supply, confirmed 2026-08-07 --
Troubleshooting below); `install-opencode.sh` will write both, and pin `options.reasoningEffort`
too if you also fill in the matching `_reasoning` key with anything other than `none`.
`validate-model-map.sh` warns (never fails) when a harness resolves high and mid to the
same value, `flexible` included, so this is never silently missed.

**Privacy:** if you pick a free model still in its free window, submitted data may be used
to improve it -- check whichever model you choose. Never run client or proprietary code
through a free-window model.

Override the whole table with `--model-map <path>` or by editing the `opencode:` block.

## CI loop workflows

Three GitHub Actions workflows run this repo's own loops headlessly on OpenCode:
`.github/workflows/triage-opencode.yml` (morning-triage), `retro-opencode.yml`
(weekly-retro), and `sync-opencode.yml` (sync) -- mirrors of the Claude-based
`triage.yml`/`retro.yml`/`sync.yml`.

These are optional OpenCode Zen examples, not a required provider choice. A local clone
does not create scheduled workflows. Fork this repository or push your clone to a GitHub
repository you control to run them; they maintain that repository only. To run scheduled
loops through another provider, configure that provider's equivalent workflow in your own
repository.

Morning triage runs daily at 06:00 UTC through `triage-opencode.yml`; weekly retro runs
Monday at 07:00 UTC through `retro-opencode.yml`; and sync runs Monday at 08:00 UTC through
`sync-opencode.yml`. All three also support manual dispatch. Their Claude counterparts
remain manual-only, so each loop has one scheduled provider. Each workflow's concurrency
group prevents overlapping runs of that loop.

They default to `opencode/muse-spark-1.3-contributor-free` (listed as free in the
OpenCode Zen documentation on 2026-09-15). This is a CI-only exception to
`config/model-map.yml`'s shipped `flexible` default: a headless run has no human present
to pick a model interactively. Each
workflow also accepts a `model` string input at dispatch time: any provider/model id
that `opencode models` lists, validated as a non-empty provider/model value before use.
There is no auto-selection fallback on purpose -- Zen's live catalog mixes in TTS,
video, embedding, and music models that cannot run an agentic loop, so a silent
substitution would trade an explicit error for a broken run. The map itself stays
untouched and flexible on every tier; if the default rotates out of Zen's free lineup,
dispatch a current id or edit these three files.

Credential prerequisite: add an Actions secret named `OPENCODE_ZEN_API_KEY` under
Settings > Secrets > Actions before the first dispatch (same name adapters/HERMES.md
uses). No CLI env-var contract for the Zen API key could be verified from primary
sources, so each workflow writes `$HOME/.local/share/opencode/auth.json` from that
secret at runtime, then fails fast via `opencode auth list` before any model call.

Repository prerequisite: under Settings > Actions > General, set **Workflow permissions**
to **Read and write permissions** and enable **Allow GitHub Actions to create and approve
pull requests**. The loop's `GITHUB_TOKEN` then creates its review pull request after a
state change; the workflow never approves, merges, or deploys it.

Privacy caveat inherited from "Model tiers and reasoning"'s **Privacy** note, generalized
to whichever model you dispatch: a free-window model may train its upstream provider's
future models under that model's own terms. These workflows must only ever operate on
this already-public repo's own content -- never repoint them at proprietary code.

## Agent visibility (Tab-cycle vs. dispatch-only)

OpenCode's `mode:` field controls whether an installed agent shows up in the Tab-cycle
switcher (`primary`), is reachable only via `@ mention` or an `sefi-agents`
dispatch (`subagent`), or both (`all` -- OpenCode's own default when `mode:` is unset).

Live-observed (2026-08-18): with no `mode:` written, every converted agent defaulted to
`all`, so all 15 -- every specialist alongside `sefi-agents` -- sit in the same
switcher as OpenCode's native `build`/`plan` agents. Nothing distinguished the one entry
point from the ones it dispatches, and a direct switch to a specialist skips every gate
that only runs on the dispatched path (`check-reply.sh`, `check-handoff.sh`,
`ready-steps.sh`'s parallel cap) -- the same failure class as the `prompt-engineer`
scope-creep bug that motivated `scope-boundary.md`.

`install-opencode.sh` now writes `mode: primary` for `sefi-agents` and
`mode: subagent` for the other 15, so the switcher shows one entry point and the
specialists remain dispatchable exactly as before. This is enforcement, not a suggestion
on top of the existing "always go through the EM" convention -- the other 15 are
structurally absent from the switcher, not just discouraged.
