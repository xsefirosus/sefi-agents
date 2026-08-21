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
(conversion table lives in the script's comments). `model:` is REPLACED with the
harness-resolved value via `config/model-map.yml`, not dropped -- see "Model tiers and
reasoning" below for why dropping it was tried once and reverted. A `mode:` field is
also written: `primary` for `engineering-manager` only, `subagent` for every other
agent, so OpenCode's own Tab-cycle switcher shows just the one entry point instead of
all 14 (see "Agent visibility" below). Every other frontmatter field and the entire body
is preserved byte-for-byte.

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

**`Model not found: sonnet/`** (or `haiku/`, `opus/`) on any subagent dispatch --
live-observed, not hypothetical: the installed agent still carries a raw `model:` line
from before this was fixed. Pull the latest sefi-agents and re-run
`install-opencode.sh --force`; the current script drops `model:` entirely so OpenCode
falls back to the session model configured in section 1, instead of trying to resolve a
Claude Code-only alias it does not recognize. This affects every agent, not just the one
that happened to fail first -- all 14 agents carry a `model:` line. If the orchestrating agent
silently falls back to a generic, unconstrained dispatch instead of surfacing this error
to you, treat that as a second problem worth stopping for: it means the task is now
running with none of the specialized agent's actual guardrails (tool whitelist, output
contract, gate requirement), not a harmless retry.

**`Model not found: <your-model>/`** (or any dispatch silently failing to resolve its
model) on an install where `config/model-map.yml`'s `opencode:` block has been edited away
from the shipped `flexible` default to name a real model -- live-observed 2026-08-07 on a
prior pinned value: the id was missing OpenCode's required `provider/model-id` prefix, the
exact same failure class as the `sonnet/` case above, just on a hand-supplied replacement
value rather than the original Claude Code alias. Fix the value in `model-map.yml` itself
(add the missing `<provider>/` prefix -- `opencode/` for a Zen model) and re-run
`install-opencode.sh --force`. This cannot happen on the shipped `flexible` default: it
writes no `model:` line at all, so there is no id for OpenCode to fail to resolve.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI secrets. See
`Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

`install-opencode.sh` resolves each agent's harness-neutral `tier:` through
`plugins/sefi-core/config/model-map.yml`. As of v0.3.18, the shipped map's `opencode:`
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

## Agent visibility (Tab-cycle vs. dispatch-only)

OpenCode's `mode:` field controls whether an installed agent shows up in the Tab-cycle
switcher (`primary`), is reachable only via `@ mention` or an `engineering-manager`
dispatch (`subagent`), or both (`all` -- OpenCode's own default when `mode:` is unset).

Live-observed (2026-08-18): with no `mode:` written, every converted agent defaulted to
`all`, so all 14 -- every specialist alongside `engineering-manager` -- sat in the same
switcher as OpenCode's native `build`/`plan` agents. Nothing distinguished the one entry
point from the ones it dispatches, and a direct switch to a specialist skips every gate
that only runs on the dispatched path (`check-reply.sh`, `check-handoff.sh`,
`ready-steps.sh`'s parallel cap) -- the same failure class as the `prompt-engineer`
scope-creep bug that motivated `scope-boundary.md`.

`install-opencode.sh` now writes `mode: primary` for `engineering-manager` and
`mode: subagent` for the other 13, so the switcher shows one entry point and the
specialists remain dispatchable exactly as before. This is enforcement, not a suggestion
on top of the existing "always go through the EM" convention -- the other 13 are
structurally absent from the switcher, not just discouraged.
