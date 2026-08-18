# Running sefi-agents on Codex

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`.

## 1. Install

Codex has a real plugin marketplace that consumes this repo's existing
`.claude-plugin/marketplace.json` unchanged. Live-verified end to end:

```sh
codex plugin marketplace add xsefirosus/sefi-agents
codex plugin add sefi-core@sefi-agents
```

The first registers the marketplace; the second installs all 14 agents, 12 skills,
hooks, commands, and templates into `~/.codex/plugins/cache/sefi-agents/sefi-core/
<version>/`.

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

Hooks: the Codex marketplace path installs hooks with the plugin, but `install.sh` does not
-- it links `agents/`, `skills/`, and `commands/` only. If you installed by hand, wire
`scripts/inject-memory.sh` to a session-start event yourself, or accept that the
memory-protocol READ ladder retrieves vault content without it.

## 4. Worktrees

Codex may create its own sandbox worktree. The worktree procedure in `docs/LOOPS.md` is
provenance-gated (only removes worktrees under `.worktrees/` or `worktrees/`), so a
Codex-created sandbox worktree is left alone.

## 5. Troubleshooting

First stop: `codex doctor` (Diagnose local Codex installation, config, auth, and runtime
health).

- **Marketplace add fails** -- check network and git access to `github.com`.
- **Plugin add reports marketplace not found** -- run `codex plugin marketplace list`
  to confirm the previous add registered, then retry the `plugin add`.
- **Agents do not seem to load** -- `codex doctor`'s Configuration section shows
  `config.toml parse: ok` and the installed plugin count; re-run
  `codex plugin add sefi-core@sefi-agents` from a clean shell if the count is wrong.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI secrets. See
`Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

Verified 2026-08-11. GPT-5.6 ships as a three-model family that lines up 1:1 with the tiers:

| Tier | Model | Reasoning | Used by |
|---|---|---|---|
| high | `gpt-5.6-sol` | `xhigh` | qa-engineer, security-engineer |
| mid | `gpt-5.6-terra` | `high` | 7 agents incl. software-engineer |
| low | `gpt-5.6-luna` | `medium` | 5 haiku-tier agents |

Sol is the flagship, Terra the balanced workhorse, Luna the fast/cheap option -- "Terra as
default, Sol for the hard parts, Luna for volume". Putting Sol on `high` is what keeps the
qa-engineer a genuinely stronger judge than the software-engineer it reviews.

Use the explicit ids. The bare `gpt-5.6` alias routes to `gpt-5.6-sol` today, which adds a
routing question to any diagnostic.

**Deadline:** `gpt-5.4` and `gpt-5.4-mini` retire from Codex on **2026-08-31**. The
documented replacements are `gpt-5.4` -> `gpt-5.6-terra` and `gpt-5.4-mini` ->
`gpt-5.6-luna`.

### Reasoning effort

`model_reasoning_effort` accepts `minimal | low | medium | high | xhigh`. Set it in
`~/.codex/config.toml`:

```toml
model = "gpt-5.6-terra"          # mid tier: the default
model_reasoning_effort = "high"
review_model = "gpt-5.6-sol"     # high tier: the adversarial judge
```

`xhigh` is only available on top-tier (codex-max) coding models, so an effort setting can
silently constrain which models make sense for a profile. If a dispatch on `gpt-5.6-sol`
rejects or ignores `xhigh`, lower `codex.high_reasoning` in the model map to `high` -- one
line, which is the point of the map.

### Baking the models in

The Codex marketplace path reads agent files directly with no transform step, so nothing
rewrites `model:` for Codex automatically, and `model:` is advisory here in any case. To
bake in the ids first:

```sh
bash plugins/sefi-core/scripts/apply-model-map.sh codex plugins/sefi-core/agents <dst-dir>
```

It resolves each agent's `tier:` through `plugins/sefi-core/config/model-map.yml`, writes
the Codex model, drops the `tier:` line, preserves everything else byte-for-byte, and
prints the matching `config.toml` block. Reasoning effort is deliberately NOT written into
frontmatter: Codex reads it from `config.toml`, so an agent-file field would be inert while
looking wired.
