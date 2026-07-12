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

The first registers the marketplace; the second installs all 13 agents, 12 skills,
hooks, commands, and templates into `~/.codex/plugins/cache/sefi-agents/sefi-core/
<version>/`.

## 2. Subagents (multi_agent)

`multi_agent` is stable and `true` by default -- no manual step needed. Confirm with
`codex features list | grep multi_agent`; if it shows anything other than `stable  true`,
run `codex features enable multi_agent` (equivalent to `-c features.multi_agent=true`).

## 3. Roster, instructions, and headless

Codex reads `AGENTS.md` as its instructions file. `model:` and `disallowedTools:` are
advisory; the gates are the hard line. Installed plugins show up in
`~/.codex/config.toml` as `[plugins."sefi-core@sefi-agents"]` with `enabled = true`.
Headless: `codex exec`. Sandbox and approval: `-s/--sandbox` and `-a/--ask-for-approval`
(unattended loops usually want `--ask-for-approval never` for routine calls).

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
