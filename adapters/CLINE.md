# Running sefi-agents on Cline (Desktop / CLI)

Thin adapter. Canonical agent/skill/command bodies live under
`plugins/sefi-core/`; this adapter only maps the runtime differences and never
duplicates them. The narrow action map is
`skills/sefi-orchestration/references/harness-actions.md`.

Scope: Cline Desktop and Cline CLI. Subagents "are available in the Cline CLI
and Cline Desktop. The VS Code and JetBrains extensions don't use them" --
[Subagents](https://docs.cline.bot/features/subagents). Do not install this
adapter expecting subagent dispatch inside the VS Code / JetBrains extensions;
that path is out of scope by Cline's own statement, not by this repo's choice.

## 1. Install paths

Cline configuration lives in two scopes -- "Global configuration in
`~/.cline/` (applies globally across all Cline applications, including IDE,
CLI, and SDK)" and "Project configuration in `.cline/` (applies only to the
current workspace)" --
[Config](https://docs.cline.bot/getting-started/config).

Global (`~/.cline/`), per that page:

- `agents/`, `skills/`, `rules/`, plus `workflows/`, `hooks/`, `plugins/`,
  `cron/` -- "Global rules, workflows, hooks, skills, agents, plugins, and
  cron specs resolve directly under `~/.cline/`."
- Structured app state under `~/.cline/data/` (`settings/providers.json`,
  `global-settings.json`, `cline_mcp_settings.json`, `teams/`, `sessions/`,
  `db/`, `logs/`).

The installer additionally lays `commands/` and `scripts/` under `~/.cline/`
(see section 2). Whether Cline natively loads `~/.cline/commands/` as a
commands directory is UNKNOWN from the two cited docs -- they are sefi
installer destinations so bundled command bodies and referenced scripts exist
on disk, not a claim about Cline-native discovery.

Project, per the same page:

- `.cline/` at the repository root: `rules/`, `workflows/`, `skills/`,
  `hooks/`, `agents/`, `plugins/`.
- The older `.clinerules/` layout is also read ("rules, plus its `workflows/`,
  `skills/` and `hooks/` folders"), as is "AGENTS.md at the project root, and
  skills in `.agents/skills/`".

Compatibility paths, per the same page:

- "Rules, hooks, plugins, and workflows may also be discovered from
  `~/Documents/Cline/` for compatibility" (`Rules/`, `Hooks/`, `Plugins/`,
  `Workflows/`).
- "Globally, it also reads `~/.agents/AGENTS.md` and skills in
  `~/.agents/skills/`" -- the cross-tool file. Workspace rule equivalents
  (`.cursorrules`, `.windsurfrules`, `AGENTS.md`) are documented under
  [Rules](https://docs.cline.bot/customization/cline-rules), which also
  confirms `.clinerules/` and `.cline/rules/` as the two supported workspace
  rule directories.

## 2. One-command install (copy mode)

From the repo root:

```sh
./install.sh --target cline --copy
```

`--target cline` loads the shipped `adapters/manifests/cline.yml`; a promoted
`verified:shipped` adapter is reached by target id, not by `--adapter`, which
accepts only `local:custom` manifests (see `install.sh`).

`--copy` is load-bearing, not stylistic. `install.sh` resolves
`${CLAUDE_PLUGIN_ROOT}` to a literal `$DEST` path in file content only in
`--copy` mode; the default symlink mode cannot rewrite without mutating the
source checkout (see `install.sh` header). Cline has no confirmed equivalent
of the `claude`-target `settings.json` `env` wiring this repo uses to close
that gap without rewriting, so copy mode is how bundled prose references the
installed scripts. The command lays `agents/`, `skills/`, `commands/`, `scripts/`, plus the shipped always-on router rule `rules/sefi-router.md` (source: `plugins/sefi-core/rules/sefi-router.md`, laid as `$DEST/rules/sefi-router.md` with the placeholder resolved in copy mode), under the
manifest destination (`${HOME}/.cline`). It refuses to overwrite without
`--force` and never auto-initializes a project: installation is user-wide and
cannot safely choose or modify a repository. From each repository you later
use, run `/sefi:init` once from that repository's root before its first
routed request. Init leaves cross-project memory off unless an interactive
user enables the local/private mirror.

## 3. Always-on routing without a session-start hook

The manifest declares `hook_strategy: none`. Cline has no confirmed
session-start hook event this repo can wire for sefi purposes -- the
hook-event map rows for Cline in `harness-actions.md` are UNKNOWN by design.
Nothing here invents one.

The substitute is the global rules auto-load. "Rules are markdown files that
provide persistent instructions across all conversations" and "have Cline
follow them automatically" --
[Rules](https://docs.cline.bot/customization/cline-rules). Global rules go in
"your system's Cline Rules directory" (`~/.cline/rules/` per section 1) and
apply across all projects. That is the always-on router: it is present every
task without anyone invoking a command.

- No `paths:` frontmatter = always-on. "Put always-on rules (coding standards,
  project conventions) in files without frontmatter" (same page). The sefi
  router rule ships this way.
- With `paths:` frontmatter = conditional (frontend/backend, test-file, and
  docs patterns on that page are the documented examples). Do not put `paths:`
  on the router rule; that would scope it out of tasks that plainly need
  routing.

This is a prompt-level instruction, not a load guarantee in the hook sense,
so an explicit `/sefi:route`-shaped request remains the deterministic path
when routing plainly should have fired and did not.

## 4. Roster (spawn_agent dispatch)

The roster maps to Cline subagent dispatch. Per
[Subagents](https://docs.cline.bot/features/subagents):

- Dispatch is the `spawn_agent` tool: "When Cline uses the `spawn_agent` tool,
  it starts a subagent."
- "Each subagent gets its own prompt and context window, does the work, and
  returns a report to the main agent. This keeps the main agent's context
  clean, and several subagents can run at the same time." One focused task
  plus self-contained instructions per subagent; independent slices run in
  parallel, dependent steps wait.
- "Approving the `spawn_agent` call approves everything the subagent then
  does: its own tool calls don't ask for approval. ... read the subagent's
  task before you approve it." Approving the call approves the whole subtree.
- Plan mode is the read-only research posture: "In Plan mode it has no tools
  for editing files" (Act mode "can read and edit files and run commands").
  Prefer Plan mode for read-only research slices. Neither mode is claimed here
  to stop every write -- Cline's own page notes `python -c` and similar can
  still write.
- Off switch: "turn off the `spawn_agent` tool: CLI: run `cline`, type
  `/settings`, and turn off `spawn_agent` on the Tools tab. Desktop: open
  Customize, select Tools, and turn off `spawn_agent`."

Limits carried over unchanged: a subagent "doesn't get MCP tools" (same
page). Whether a dispatched subagent can itself dispatch (nested `spawn_agent`
depth, tool availability inside a subagent beyond the MCP exclusion) is
UNKNOWN from the cited page -- Cline states only that "[a] subagent can start
subagents of its own." Keep dispatch authority at the top-level session unless
a live session proves otherwise.

If `spawn_agent` is unavailable in a session (toggled off, or an extension
without subagents), execute the roster sequentially in-context and state that
explicitly rather than pretending parallelism exists. That is the
`harness-actions.md` fallback, restated here because this adapter's whole
parallelism story depends on one tool being present.

## 5. Run a systems audit

After `/sefi:init`, ask in natural language (no Cline-specific
skill-invocation sigil is confirmed from the cited docs, so none is claimed
here), for example:

```text
Run the systems-audit skill for the build scope.
```

Use one of `complete`, `research`, `product`, `design`, `build`, `quality`,
`docs`, or `delivery`. The top-level orchestrator owns dispatch, the skill
supplies the evidence method, and `systems-auditor` writes the report without
dispatching another agent or modifying source. Reports are written to
`audits/audit-report-<scope>-<timestamp>-<session>.md`. The workflow is on
demand only: no shipped loop and no scheduled workflow invokes it. An audit
report path that already exists is refused rather than overwritten, and a path
that resolves outside the audited project's own `audits/` directory is
rejected before any write.

## 6. Scheduling

UNKNOWN. No Cline scheduled trigger is mapped in `harness-actions.md` and none
is claimed here. Do not port another harness's cron event name as a guess.

## Troubleshooting

- `spawn_agent` missing or toggled off -- the roster runs sequentially
  in-context. State that explicitly in the reply; do not present sequential
  work as parallel dispatch.
- Wrong product -- subagent behavior missing inside VS Code / JetBrains is
  expected per the scope note above, not a bug in the install. Move to Cline
  Desktop or Cline CLI.
- Router rule not firing -- check the rule is in `~/.cline/rules/` with no
  `paths:` frontmatter (section 3) and toggled on; a `paths:`-scoped rule only
  activates on matching context.
- Placeholder unresolved (`${CLAUDE_PLUGIN_ROOT}` literal in installed files)
  -- re-run the section 2 command with `--copy`; symlink mode never resolves
  it in file content.
- Headless invocation, hook wiring, and per-agent model overrides on Cline
  are UNKNOWN -- not confirmed from the cited docs or the repo. Anything below
  not confirmable from those sources is UNKNOWN by policy, never a guessed
  field.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI
secrets. See `Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

Cline takes its model from whatever you have configured in Cline; no Cline
config key for that choice is claimed here (UNKNOWN -- the cited config page
names provider/settings files but this adapter invents no key). The
`plugins/sefi-core/config/model-map.yml` `cline:` block maps every tier to the
sentinel `flexible`, not a concrete model id, so tiers resolve at dispatch time
rather than being baked into an installed file:

| Tier | Model | Reasoning |
|---|---|---|
| high | `flexible` | (unset) |
| mid | `flexible` | (unset) |
| low | `flexible` | (unset) |

`flexible` means: pass no tier-specific model at dispatch -- every dispatch
runs on the Cline configured model. Reasoning effort is likewise left
untuned by this adapter, since a hardcoded value may not exist or mean the
same thing on whatever model you picked.

All three tiers share one model here, so the qa-engineer judges on the same
model it judges. Keep the adversarial reading strict to compensate -- the
generator/evaluator separation survives in instructions only. Point
`cline.high` at a different, stronger real model in `model-map.yml` the moment
you have two you can name.

## Route evidence

Not-applicable per `adapters/manifests/cline.yml` (`route_evidence:
not-applicable`). There is no Cline route-evidence check to run and none is
claimed.


