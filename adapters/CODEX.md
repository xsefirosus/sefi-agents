# Running sefi-agents on Codex

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`.

## 1. Install

Codex has a native marketplace and plugin manifest in `.agents/plugins/marketplace.json`
and `plugins/sefi-core/.codex-plugin/plugin.json`. Install it with the one-time bootstrap:

```sh
git clone https://github.com/xsefirosus/sefi-agents.git
cd sefi-agents
bash install-codex.sh
```

The script registers the marketplace when needed, refreshes its Git snapshot, reinstalls
`sefi-core@sefi-agents`, and writes only Sefi's marked block to
`${CODEX_HOME:-~/.codex}/AGENTS.md`. It preserves every other global instruction. Start a
new Codex session afterward and accept the one-time Sefi hook-trust prompt when Codex
shows it.

That global instruction is the always-on activation point: every normal user prompt in
every project loads `sefi-core:sefi-orchestration` before work begins. You do not need a
`/sefi:*` command for each prompt. The routing skill still uses its documented trivial-task
exception, so a short question does not mechanically spawn specialists.

The installed package contains all 16 agents, 19 skills, hooks, commands, and templates.
Re-run `bash install-codex.sh` after an update; it refreshes the marketplace and replaces
only its own marked instruction block and Sefi's own custom-agent model fields.

The bootstrap is user-wide. From each repository you later use, run `/sefi:init` once from
that repository's root before its first routed request. It cannot be done automatically at
install time because the bootstrap cannot safely choose or modify a project. Init leaves
cross-project memory off unless an interactive user enables the local/private mirror.

## 2. Subagents (multi_agent)

`multi_agent` is stable and `true` by default -- no manual step needed. Confirm with
`codex features list | grep multi_agent`; if it shows anything other than `stable  true`,
run `codex features enable multi_agent` (equivalent to `-c features.multi_agent=true`).

## 3. Roster, instructions, and headless

Codex reads `AGENTS.md` as its instructions file. `model:` and `disallowedTools:` are
advisory; the gates are the hard line. Concretely: Codex has no per-agent mechanism to stop
a Bash-capable agent from writing file content by other means (`sed -i`, `tee`, shell
redirection) even though its `disallowedTools:` line says it never does -- the same live-
confirmed gap `scripts/check-bash-write.sh` closes on Claude Code and
`install-opencode.sh`'s `bash:` permission map closes on OpenCode. Codex's own lever,
`-s/--sandbox` and `-a/--ask-for-approval` below, is session-wide, not per-agent, so it
cannot single out research-analyst or qa-engineer while leaving software-engineer free to
write. Stated honestly rather than left implicit: this is an open gap on Codex today.
Installed plugins show up in
`~/.codex/config.toml` as `[plugins."sefi-core@sefi-agents"]` with `enabled = true`.
Headless: `codex exec`. Sandbox and approval: `-s/--sandbox` and `-a/--ask-for-approval`
(unattended loops usually want `--ask-for-approval never` for routine calls).

Hooks: Codex discovers `hooks/hooks.json` from the native plugin package but requires a
visible one-time trust decision before it executes plugin commands. The bootstrap never
writes a trust hash and never uses Codex's hook-trust bypass. If you decline the prompt,
the global `AGENTS.md` routing instruction still works; only the SessionStart memory/role
injection is unavailable until you accept trust in a later new session.

Codex's documented hook here is SessionStart. It has no documented first-routed-request
event, so this adapter does not pretend to install a one-time route reminder. The successful
install message is the reminder to initialize each project before its first routed request.

The cross-project memory mirror (`memory-protocol/SKILL.md` WRITE step 4) needs none of
the hook wiring above -- `resolve-shared-memory-path.sh` and `write-shared-memory-mirror.sh`
are plain bash the Memory Journalist runs directly at close_out, so they work identically
on Codex with no per-harness code. `/sefi:init`'s harness marker (`.sefi/harness`) is
written by whichever agent runs `/sefi:init`, so Codex writes `codex` there itself, the same
way Claude Code writes `claude` -- no install-time step or Codex-specific gap. One real
caveat, not Codex-specific: a sandbox that disallows writes outside the project directory
makes the mirror fail closed by design, same as a detected ephemeral environment -- the
project-local vault write is never affected either way.

## 4. Worktrees

Codex may create its own sandbox worktree. The worktree procedure in `docs/LOOPS.md` is
provenance-gated (only removes worktrees under `.worktrees/` or `worktrees/`), so a
Codex-created sandbox worktree is left alone.

## 5. Troubleshooting

First stop: `codex doctor` (Diagnose local Codex installation, config, auth, and runtime
health).

- **Bootstrap fails before install** -- confirm `codex` is on `PATH`, then run
  `codex doctor` and retry `bash install-codex.sh`.
- **Marketplace source conflict** -- the bootstrap refuses to replace an existing
  `sefi-agents` marketplace that points somewhere else. Inspect
  `codex plugin marketplace list --json`, correct that configuration yourself, then retry.
- **Sefi does not route a new prompt** -- start a new session and inspect
  `${CODEX_HOME:-~/.codex}/AGENTS.md` for the one managed Sefi block. Re-run the bootstrap
  if it is missing.
- **Hook trust was declined** -- start another new session and accept Codex's Sefi hook
  trust prompt. Routing does not require this step; memory SessionStart injection does.
- **Sefi specialist has the wrong model** -- re-run `bash install-codex.sh`. It updates
  only `model` and `model_reasoning_effort` in Sefi's 13 custom-agent profiles under
  `${CODEX_HOME:-~/.codex}/agents`; it does not change your global Codex default or any
  unrelated custom agent.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI secrets. See
`Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

The bootstrap configures these exact custom-agent overrides, all at high reasoning:

| Role | Model | Reasoning | Used by |
|---|---|---|---|
| orchestration | `gpt-6-astra` | `high` | sefi-agents / engineering-manager |
| high | `gpt-5.6-sol` | `high` | qa-engineer, security-engineer |
| mid | `gpt-5.6-terra` | `high` | software-engineer, product-manager, ui-ux-designer, devops-engineer, solutions-architect |
| low | `gpt-5.6-luna` | `high` | prompt-engineer, research-analyst, codebase-cartographer, adoption-scout, support-engineer, memory-journalist, technical-writer |

The plugin does not change the model of the top-level conversation you start. It assigns
the selected model only when Codex dispatches one of these Sefi custom agents.

Use the explicit ids. The bare `gpt-5.6` alias routes to `gpt-5.6-sol` today, which adds a
routing question to any diagnostic.

### Reasoning effort

`model_reasoning_effort` is set to `high` directly in each Sefi custom-agent profile.
Codex applies a custom agent's explicit model and effort when that specialist is dispatched;
your global `config.toml` settings remain the defaults for your own top-level and unrelated
agents.

If you want the same baseline for non-Sefi work, set it yourself in `~/.codex/config.toml`:

```toml
model = "gpt-5.6-terra"          # mid tier: the default
model_reasoning_effort = "high"
review_model = "gpt-5.6-sol"     # high tier: the adversarial judge
```

### Baking the models in

`install-codex.sh` is the supported path. After Codex creates its Sefi custom-agent
profiles, the bootstrap resolves each profile through `config/model-map.yml` and writes
only its `model` and `model_reasoning_effort` fields. The `sefi-agents` profile is the
deliberate orchestration exception and resolves to Astra; the other profiles resolve from
their high/mid/low tier.

`apply-model-map.sh` remains available for an isolated converted copy of the Markdown
agent sources:

```sh
bash plugins/sefi-core/scripts/apply-model-map.sh codex plugins/sefi-core/agents <dst-dir>
```

It resolves each agent through `plugins/sefi-core/config/model-map.yml`, including the
Codex orchestration exception, writes the model, drops the `tier:` line, and preserves
everything else byte-for-byte.

## Session rollout

Codex writes a per-thread session rollout that the post-dispatch route-evidence check
(`${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh`, whose parser is the sibling
`check-route.py`) reads to confirm a dispatch ran the model + reasoning effort the tier map
asked for. This section documents the format the check depends on. Its shape is
reverse-engineered from the MIT-licensed astral-orchestrator reader --
`check-primary.py:82-101` (the sessions-directory resolution and rollout-filename match)
and `inspect-agent-runtime.sh:84-231` (the embedded stdlib-Python rollout reader) -- plus
Codex's public session-logging documentation. Anything below not confirmable from those two
sources is marked UNKNOWN and the check treats it as such (fail-noisy `invalid`, never a
guessed field).

- **Location.** `${CODEX_HOME:-~/.codex}/sessions`, searched **recursively** (Codex nests
  rollouts in dated subdirectories). `check-route.sh` honors `CODEX_HOME`; a test-only
  `--sessions-dir PATH` override widens the read scope and nothing else.
- **Filename.** `rollout-*-<thread-id>.jsonl`, where `<thread-id>` is a **lowercase UUID**
  (`[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`). The check matches
  rollout **filenames only** -- exactly one match is read; zero is `unavailable`, more than
  one is `invalid` (ambiguous).
- **Line shape.** One JSON object per line (JSONL). Every record has a top-level string
  `type` and a top-level object `payload`. The check parses each line with a real JSON
  parser and only ever inspects those two **top-level** keys -- it never descends into a
  nested object, so a `type`/`model` pair nested inside some other record's `payload`
  is not a route signal.
- **`turn_context` record.** `type == "turn_context"`; its `payload` carries the effective
  route as two string fields, `payload.model` (a bare model identifier, e.g.
  `gpt-5.6-terra`) and `payload.effort` (a reasoning-effort word). The check reads only
  `model` and `effort` from this record -- never any other `payload` field, never rollout
  free text (prompts, reasoning, tool output, cwd).
  - `payload.effort` accepts `minimal | low | medium | high | xhigh` (the values Codex's
    `model_reasoning_effort` documents, see `### Reasoning effort` above) plus `none` and
    `ultra`, which `check-route.py`'s allowlist also permits -- `none` = a tier that
    exposes no reasoning dial, `ultra` = an explicit maximum. Neither `none` nor `ultra`
    appears in Codex's public `model_reasoning_effort` docs (source UNKNOWN); they are
    carried only so a rollout that happens to use them is not spuriously rejected as
    `invalid`. The allowlist is deliberately a superset, never narrower than what a real
    rollout might contain.
- **Last-wins.** A forked rollout snapshot legitimately contains several `turn_context`
  records (inherited parent contexts). The **last** top-level `turn_context` is the
  effective route for the thread; earlier ones are ignored. A malformed last record fails
  as `invalid` -- it never falls back to an earlier good one.
- **`CODEX_THREAD_ID`.** The environment variable carrying the current thread's id, passed
  to `check-route.sh` as its third argument after a dispatch. A literal `-` (or empty)
  means "no thread id available" and yields `unavailable`.

UNKNOWN, not confirmed from the two cited sources or Codex's public docs:

- the full `payload` schema of a `turn_context` record beyond `model` / `effort` (astral's
  reader also reads `sandbox_policy` / `permission_profile` / `cwd`, but whether those keys
  and their nesting are stable across Codex versions is not documented here);
- the `session_meta` record's exact schema (only that it appears first and its `payload.id`
  is the thread id);
- whether `CODEX_THREAD_ID` is **always** exported into a dispatched agent's environment,
  or only under certain sandbox / approval modes;
- the rollout's rotation / retention policy and whether a single thread can span more than
  one `rollout-*-<thread-id>.jsonl` file.

Because these are UNKNOWN, the live route check is **Codex-only and fixture-validated**: a
confirmation run against a real rollout on a live Codex host is a follow-up, not a claim of
the current implementation.
