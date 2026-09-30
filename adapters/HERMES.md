# Running sefi-agents on Hermes Agent (free-model mode)

Hermes runs the roster on a free model. Canonical agent/skill/command bodies live under
`plugins/sefi-core/`; this adapter only maps the runtime differences and never duplicates
them. The narrow action map is `skills/sefi-orchestration/references/harness-actions.md`.

## 1. Point Hermes at OpenCode Zen (OpenAI-compatible)
- Base URL: `https://opencode.ai/zen/v1`
- Model: your choice -- OpenCode Zen's free lineup rotates (`deepseek-v4-flash-free` was
  verified real on 2026-08-11 and retired by 2026-08-21, ten days later), so this doc no
  longer names one. Check Zen's current model list and pick a free or paid model yourself.

```sh
hermes config set provider.base_url https://opencode.ai/zen/v1
hermes config set provider.model    <your-chosen-model>
hermes config set provider.api_key  "$OPENCODE_ZEN_API_KEY"
```

Precedent: a predecessor system already ran Hermes on an OpenCode Zen free model
(`mimo-v2.5-free`), so this pairing is proven, not speculative -- just not tied to any one
model, since Zen's own free catalog has already turned over more than once.

## 2. Caveats (the caps and the qa-engineer are load-bearing here, not garnish)
- Free-window models may train on submitted data -- never run client or proprietary code
  through them.
- Rate limits make the budget caps and `max_retries` mandatory, not optional.
- Run overnight loops via cloud CI or `hermes cron`, not an always-on local process.
- Calibrate expectations: a predecessor system's tracked free-model dispatch success was ~45%, workable
  only because gates and human checkpoints catch the other half.

## 3. Sync skills
See section 8 below (`install-hermes.sh`) for the tested, real install path -- it uses
Hermes's own `skills install` command per skill, not a raw copy, so installs are scanned,
tracked, and show up correctly in `hermes skills list`.

`install-hermes.sh` installs skills only, plus the managed canonical runtime. It installs
no hooks. Neither does `install.sh` for this harness: it delegates the `opencode` target to
`install-opencode.sh`, and it merges `hooks/hooks.json` into `settings.json` only for its
`claude` target. The SessionStart memory therefore ships through the Claude Code plugin
path, so on Hermes you must wire `inject-memory.sh` to a session-start event yourself.
Nothing breaks without it: the memory-protocol READ ladder (frontmatter scan -> index ->
at most 2 notes) is what actually retrieves vault content; the injection is an optimization
on top of it.

Hermes has no confirmed hook event for a first routed request, so this adapter installs no
one-time route reminder. The successful installer message tells users to run `/sefi:init`
from each project root before that request. Init keeps the optional local/private
cross-project memory mirror off unless an interactive user enables it.

### Run a systems audit

Hermes installs the `systems-audit` skill and its managed canonical runtime. Ask for an
audit in natural language after `/sefi:init`, for example:

```text
Run the systems-audit skill for the build scope.
```

Use one of `complete`, `research`, `product`, `design`, `build`, `quality`, `docs`, or
`delivery`. The top-level orchestrator owns dispatch, the skill supplies the evidence
method, and `systems-auditor` writes the report without dispatching another agent or
modifying source. Reports are written to
`audits/audit-report-<scope>-<timestamp>-<session>.md`. Local memory search and
`/sefi:memory-index rebuild` include audit reports; cross-project memory mirroring refuses
them. The installer provides no Hermes slash command for this workflow.

The workflow is on demand only: no shipped loop and no scheduled workflow invokes it, and
Hermes contributes no scheduled trigger of its own. An audit report path that already
exists is refused rather than overwritten, so a follow-up audit is a new timestamped file,
and a path that resolves outside the audited project's own `audits/` directory is rejected
before any write.

The cross-project memory mirror (`memory-protocol/SKILL.md` WRITE step 4) needs none of
the hook wiring above -- `resolve-shared-memory-path.sh` and `write-shared-memory-mirror.sh`
are plain bash the Memory Journalist runs directly at close_out, so they work identically
on Hermes with no per-harness code. `.sefi/harness` is written by `/sefi:init` as the
literal harness name at scaffold time, same as on every harness. One real caveat, not
Hermes-specific: a sandbox that disallows writes outside the project directory makes the
mirror fail closed by design, same as a detected ephemeral environment -- the project-local
vault write is never affected either way.

## 4. Roster
The roster maps to Hermes subagent delegation. `model:` and `disallowedTools:` are advisory
on Hermes, so treat the whitelist as a soft contract; the gates are the hard enforcement.
Concretely: a `delegate_task` granted the `terminal` toolset almost certainly has the same
Bash-content-write bypass as Claude Code's `Bash` tool -- it can write file content by
shell means (`sed -i`, `tee`, redirection) regardless of what the agent's
`disallowedTools:` line says, since that field is not read by Hermes at all. This is the
same live-confirmed gap `scripts/check-bash-write.sh` closes on Claude Code and
`install-opencode.sh`'s `bash:` permission map closes on OpenCode. Stated honestly: this
repo has no live Hermes access to build or verify an equivalent gate, so it is an open gap
here. If Hermes's own toolset system supports per-command restriction within `terminal`
(unconfirmed), that would be the place to enforce it -- not this repo's `disallowedTools:`
field, which Hermes never consults.

## 5. Scheduling
Loop triggers map to `hermes cron`.

## 6. Self-improvement coexistence
Hermes' curator touches only its own created skills; sefi's retro loop edits only
`managed-by: sefi-agents` files. They are disjoint by construction. If you prefer, set
`improvement.enabled: false` in `sefi.config.yml` and let the host own learning.

## 7. Local gateway + delegate_task facts (live-verified in a predecessor system)
Every constraint below was discovered by hitting it.

| Fact | Detail |
|---|---|
| Gateway | local OpenAI-compatible: `POST http://localhost:8642/v1/chat/completions` (bearer `HERMES_API_KEY`); `GET /v1/capabilities` = 5s health probe; `GET /v1/skills` = skill list; responses carry a real `usage` block -- record it |
| Dispatch | prompt-instructed, not API-called: instruct Hermes' agent to call its own `delegate_task(tasks=[{goal,context,toolsets,...}], role="orchestrator", background=true)`, tasks array inlined verbatim |
| Reserved `role` | agent-hierarchy field ("orchestrator" / "leaf") -- never reuse for specialist type (collision silently coerces to 'leaf'); use `specialist_role`. `tasks` is required |
| Concurrency | `max_concurrent_children = 3` (hard cap). Batch client-side to <= 3 per call -- never prompt-side (a predecessor's self-batching hit 1.36M tokens and re-ran completed tasks) |
| Timeout | delegation gets its own longer budget (900s vs the 300s default that killed a live 12-task dispatch) |
| Output dir | every task names its absolute output dir plus one example joined path -- else dispatches write to the home directory |
| Toolsets | `terminal` / `file` / `database` / `docker` dispatch cleanly; grant `browser` only after verifying it works |
| Parsing | every reply through the parse ladder (see sefi-orchestration); log the raw head/tail on failure |

## 8. One-command skill install

Hermes has no bulk-install verb, so a single `cp` won't do. From the repo root:

```sh
bash plugins/sefi-core/scripts/install-hermes.sh
```

The script loops the real `hermes skills install <owner>/<repo>/<path>` command once per
skill (all 20). After the loop it derives success from `hermes skills list` and a
byte-for-byte comparison with the expected source, rather than from the per-call exit code,
because hermes exits 0 even on a BLOCKED scanner verdict.

Two skills are attempted with `--force` because hermes's community-skill scanner can
flag their *content* on substring match: `sefi-orchestration` (its references name
subagent dispatch / hooks / shell) and `security-review` (its checklist names
dangerous patterns to warn against them). On this Hermes version, `--force` does not
override a `DANGEROUS` verdict. The script still attempts all 20 skills, verifies the
real installed set and fetched bytes, reports any missing names, and exits 1 when the
verified count is incomplete or content differs. The other 18 stay on the default no-override
path.

Hermes has no discrete agent-install command. The installer keeps a managed canonical
runtime at `sefi-core/` beside the path returned by `hermes config path`; it contains the
agents, skills, scripts, config, commands, and templates needed by installed references.
The installed `systems-audit` report contract resolves the validator and formatter from
that runtime. The roster maps to Hermes subagent delegation via `delegate_task(...)` (see
row 3 of section 7 above).

Containment is enforced, not assumed. The installer refuses a skills root that is not a
real directory, a symlinked live skill, a symlinked managed runtime, and symlinked content
inside either the source checkout or the runtime. It refuses a managed file whose
installed path escapes the runtime root, and refuses a rollback or cleanup target outside
its own quarantine directory. Each refusal names the offending path and exits non-zero
rather than writing through it; fix the path on disk and re-run.

### Updating an existing install (`--auto-update`)

Every install records the laid-down source version (`source_version` and `source_commit`)
and per-managed-file SHA-256 hashes in `sefi-core/.sefi-agents-manifest.json`. Re-running
with `--auto-update` compares that managed runtime against the current checkout:

- No differences -- the runtime is current and stays untouched.
- A source-revision or source-file mismatch (`stale`) -- refreshes only verified managed
  files and preserves unrelated runtime content.
- A changed managed file (`drift`) -- stops with an error naming it rather than overwriting.
- A legacy skill-only installation has no runtime, so `--auto-update` adds it. An existing
  runtime without a valid manifest stops as unclassifiable.

Recording and checking the runtime needs Python 3.11+; without it the installer refuses to
guess. Candidate-checkout simulations prove local installer behavior. Public-source smoke
checks verify downloaded release bytes only after publication.

### If sefi-orchestration / security-review still show as missing

`--force` does not guarantee a pass -- the scanner's verdict is not fully deterministic.
When the installer reports a missing skill or mismatched bytes, it leaves the managed runtime
unchanged. Resolve the fetch issue and rerun the installer so the native skill and canonical
runtime remain a matched set.

## Troubleshooting

- `hermes doctor --fix` ("Diagnose issues with Hermes Agent setup", with an
  auto-remediate flag) -- run this first for any install/config problem.
- `hermes hooks doctor` ("Check each configured hook: exec bit, allowlist, mtime
  drift, JSON validity, and synthetic run timing") -- useful only once you have wired the
  memory-injection hook yourself (see section 3). No sefi installer creates it on Hermes, so
  on a stock install this reports nothing about sefi.
- **GitHub API rate limit exhausted** -- `install-hermes.sh` makes 20 fetches per run
  (one per skill); Hermes's unauthenticated GitHub API limit is 60 requests/hour, so
  a few re-runs (or other GitHub activity sharing the same limit) can exhaust it. The
  install output says so directly ("GitHub API rate limit exhausted") rather than
  failing silently. Fix: wait for the hourly reset, or set `GITHUB_TOKEN` (or run
  `gh auth login` if the `gh` CLI is installed) to raise the limit to 5,000/hour, then
  re-run the script. Live-observed side effect of hitting this mid-session: one install
  attempt silently resolved to an unrelated, same-named third-party skill from a
  different source instead of erroring cleanly -- if an installed skill's content looks
  wrong, check `hermes skills list`'s Source column (`skills.sh` is this repo; anything
  else is not) and re-install once the limit resets.

## Credentials

sefi stores no credentials -- rotate at this harness's own config or your CI secrets. See
`Install.md`'s Operating Rules for the canonical statement.

## Model tiers and reasoning

Hermes takes its model from the global `provider.model` setting (section 1) and treats
per-agent `model:` as advisory, so tiers are resolved at DISPATCH time rather than baked
into a file. The shipped `config/model-map.yml` `hermes:` block maps every tier to the
sentinel `flexible`, not a concrete model id -- Hermes was already the least-hardcoded
harness (it never wrote a model into an installed file to begin with), so this just stops
`model-for.sh` from handing back an id that might already be dead by the time it's read:

```sh
bash plugins/sefi-core/scripts/model-for.sh hermes high              # -> flexible
bash plugins/sefi-core/scripts/model-for.sh hermes high --reasoning  # -> none
```

| Tier | Model | Reasoning |
|---|---|---|
| high | `flexible` | (unset) |
| mid | `flexible` | (unset) |
| low | `flexible` | (unset) |

`flexible` means: don't pass a tier-specific model into `delegate_task(...)` at all --
every dispatch runs on whatever you set `provider.model` to in section 1. Reasoning effort
is likewise left to you to tune, since a hardcoded value (`max`/`high`/`medium`, DeepSeek V4
Flash's own dial) may not exist or mean the same thing on whatever model you pick.
The mid-tier systems-auditor resolves the same way -- its audit dispatches run on
`provider.model` with no per-tier override.

All three tiers share one model here, so the qa-engineer judges on the model it is judging.
That is not new: the previous pinned-to-one-free-model setup paid the identical price,
just silently. Point `hermes.high` at a different, stronger real model in `model-map.yml`
the moment you have two you can name -- `delegate_task(...)` will then get a real per-tier
id again instead of `flexible`. The free-window training caveat in section 2 applies
unchanged to whatever model you choose.
