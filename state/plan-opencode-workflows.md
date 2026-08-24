## Objective
Ship three OpenCode-based CI workflows -- headless mirrors of the existing Claude-based
`triage.yml`, `retro.yml`, and `sync.yml` -- so the morning-triage, weekly-retro, and sync
loops can each also run on OpenCode against a pinned free model, `Muse Spark 1.2 Contributor
Free` (Meta, served via OpenCode Zen). This is genuinely unbuilt ground: no workflow in this
repo has ever invoked the OpenCode CLI, and `adapters/OPENCODE.md` documents only the
interactive path (a human runs `/models` and picks one). CI has no human, so this plan pins a
concrete model where the interactive adapter deliberately does not.

Owner decision taken as given (asked and answered before this plan was written): use
`Muse Spark 1.2 Contributor Free` as the pinned model for these three workflows.

Why this does NOT touch `config/model-map.yml`'s shipped `opencode:` block (still `flexible`
on all three tiers): that file's own comment explains the sentinel exists because Zen's free
catalog rotates and a prior pin (`deepseek-v4-flash-free`) died ten days after being verified.
Nothing about that risk has changed. The pin this plan adds lives ONLY in the three new
workflow files' own `env`/invocation, scoped to CI where a concrete value is structurally
required (no human present to fall back to). Local/interactive OpenCode installs keep
resolving through the unchanged `flexible` default. If `Muse Spark 1.2 Contributor Free`
rotates out of Zen's free lineup later, only these three workflow files need an edit -- exactly
the blast radius `model-map.yml`'s own design already argues for.

**Verification gap, stated plainly.** This plan was written by a session whose network egress
blocks `opencode.ai`, `pi.dev`, and `news.ycombinator.com` directly (confirmed via `curl` and
`WebFetch`, both returned `EGRESS_BLOCKED`/403). What is known comes from `WebSearch` result
snippets only, not a fetched primary source:
- Model id, moderately confident: `muse-spark-1-2-contributor-free` (visible in a `pi.dev`
  results-page URL: `pi.dev/models/opencode/muse-spark-1-2-contributor-free`), provider Meta
  (`@aiatmeta`), free tier name "Contributor Free" -- per an OpenCode X/Twitter post snippet,
  data submitted may train future Meta models (same privacy shape `adapters/OPENCODE.md`
  already warns about for any free-window model).
- CLI package, moderately confident: npm package `opencode-ai`, install via
  `npm install -g opencode-ai` (per `WebSearch` synthesis of `npmjs.com/package/opencode-ai`
  and independent how-to-install blog snippets; not independently fetched).
- UNKNOWN, not guessed: the exact `opencode run` non-interactive model-selection mechanism
  (CLI flag vs. `opencode.json` field vs. env var), and whether the free Contributor tier
  needs any credential/API key in a headless CI runner at all versus only interactive OAuth.

Step 1 below exists specifically to close that gap with a real tool call before anything is
written into a committed YAML file, matching this repo's own anti-hallucination discipline
(unverified stays UNKNOWN, not asserted) and `model-map.yml`'s own precedent of stating how
and when each entry was actually verified.

## Steps
- [x] 1. Install the OpenCode CLI in a scratch/CI-like shell and verify it for real. (needs: -)
  Run `npm install -g opencode-ai`, then `opencode --version`. If the package name or install
  command from this plan's research is wrong, the failure is immediate and loud -- fix the
  command here before touching any workflow file. Do not proceed to step 2 on an unconfirmed
  install.
  CONFIRMED (executed 2026-08-23 on this machine): `npm install -g opencode-ai`
  installed cleanly (3 packages); `opencode --version` -> `1.18.21`. Both the package
  name and the install command from this plan's research were correct.
- [x] 2. Verify the model id and the non-interactive model-selection mechanism. (needs: 1)
  Run `opencode models` (or the closest current equivalent -- `opencode --help` / `opencode run
  --help` if that subcommand doesn't exist) and confirm `muse-spark-1-2-contributor-free`
  (under the `opencode/` provider prefix per `adapters/OPENCODE.md` section 1's stated
  requirement) is really listed. Confirm how `opencode run` takes a model non-interactively --
  a `--model` flag, an `opencode.json` field, or an env var -- from the CLI's own `--help`
  output or `opencode debug config`, not from a guess. Record the exact confirmed invocation
  (e.g. `opencode run --model opencode/muse-spark-1-2-contributor-free "<prompt>"`) here in
  this plan file before step 4. If the id has already rotated out, stop and report back rather
  than silently substituting a different free model -- that substitution is the owner's call,
  the same principle `model-map.yml`'s own header argues for.
  CONFIRMED (executed 2026-08-23 on this machine): `opencode models` lists
  `opencode/muse-spark-1.2-contributor-free` -- the real id uses DOTS in `1.2`,
  correcting this plan's dashed WebSearch-derived guess (`muse-spark-1-2-contributor-free`
  was a pi.dev URL-slug artifact). Same model (Muse Spark 1.2 Contributor Free), same
  `opencode/` provider prefix adapters/OPENCODE.md requires -- NOT a rotation, no
  substitution made. Non-interactive selection confirmed from `opencode run --help`:
  `-m, --model` takes `provider/model`. Confirmed invocation:
  `opencode run -m opencode/muse-spark-1.2-contributor-free "<prompt>"`. A live dispatch
  with that exact form resolved the model and reached Zen's API, returning only
  `Rate limit exceeded` (free-tier throttle) on two tries -- id resolution verified
  end-to-end; completion blocked only by throttling at execution time.
- [x] 3. Resolve the credential requirement, if any. (needs: 2)
  Determine whether `Muse Spark 1.2 Contributor Free` needs an API key/token in a headless
  runner (distinct from an interactive OAuth login a human would do once locally). If yes,
  name the exact secret this plan expects (e.g. `OPENCODE_API_KEY`) so step 4-6's workflow
  `env:` blocks are correct on the first write, and note in this plan's Risks section that the
  repo owner must add it under Settings > Secrets > Actions before first run -- same posture
  `triage.yml` already takes for `ANTHROPIC_API_KEY`. If the free tier needs no key at all in
  CI, state that explicitly rather than leaving the question open.
  RESOLVED (2026-08-23): a credential IS required. Verified on this machine: the OpenCode
  Zen API credential lives in `~/.local/share/opencode/auth.json` under key `opencode`,
  shape `{type: "api", key: <secret>}` (confirmed via `opencode auth list`, which prints
  that exact path, plus JSON structure inspection; the value itself was never read or
  printed). `opencode debug paths` confirms data dir = `~/.local/share/opencode`.
  Expected Actions secret name: `OPENCODE_ZEN_API_KEY` (repo precedent: adapters/HERMES.md
  uses that exact name for Zen API keys). Headless injection: NO CLI env var for the Zen
  key could be verified from available primary sources (installed-binary string scan empty;
  `opencode debug config` exposes none; models.dev catalog has no Zen entry), so the three
  workflows will instead WRITE `auth.json` into `$HOME/.local/share/opencode/` from the
  injected secret at runtime, then verify with `opencode auth list` before any model call
  -- mechanism verified by construction, not an asserted env-var contract.
- [x] 4. Write `.github/workflows/triage-opencode.yml`. (needs: 1, 2, 3)
  Model on `triage.yml`'s structure (checkout with `fetch-depth: 0`, ripgrep install,
  `probe-tools.sh` preflight, budget-check step, commit-to-branch-and-open-PR ending, never
  merge). Differences from `triage.yml`: install `opencode-ai` instead of
  `@anthropic-ai/claude-code`; invoke via the step-2-confirmed `opencode run` form instead of
  `claude --print --dangerously-skip-permissions`; `workflow_dispatch` ONLY -- no `schedule:`
  block. State why in a header comment: the three Claude-based loops already run on cron as of
  the 2026-08-23 audit remediation, and adding a second scheduled runner over the same loop
  and the same `state/` files multiplies the untested-collision risk
  (`docs/LOOP-FAILURE-MODES.md` S3) rather than the coverage. Manual dispatch is a deliberate,
  smaller first step; enabling a schedule here is a separate future owner decision, not this
  plan's to make.
- [x] 5. Write `.github/workflows/retro-opencode.yml`. (needs: 1, 2, 3)
  Same shape as step 4, mirroring `retro.yml`. `workflow_dispatch` only, same rationale.
- [x] 6. Write `.github/workflows/sync-opencode.yml`. (needs: 1, 2, 3)
  Same shape as step 4, mirroring `sync.yml`. `workflow_dispatch` only, same rationale.
- [x] 7. Document the new option in `adapters/OPENCODE.md`. (needs: 2, 3)
  New short section next to the existing "Model tiers and reasoning" section: these three
  workflows exist, are manual-dispatch only, pin `opencode/muse-spark-1-2-contributor-free`
  specifically for CI (where the shipped `flexible` default cannot apply -- no human present
  to pick interactively), and inherit the same free-window privacy caveat already stated
  there (submitted data may train future Meta models -- never point these workflows at
  proprietary code; they only ever operate on this already-open-source repo's own content).
- [x] 8. Add a one-line Notes-column mention in the README harness table for OpenCode. (needs: 7)
  Point at `adapters/OPENCODE.md`'s new section rather than duplicating the explanation --
  match the existing terse style of that table's other cells.
- [x] 9. CHANGELOG entry and version bump. (needs: 4, 5, 6, 7, 8)
  Name this as new, additive capability (not a fix), list the three new workflow files, state
  the manual-dispatch-only scope and the pinned-model exception to `model-map.yml`'s
  `flexible` default, and link back to this plan file the way the 0.4.1 entry already links
  the audit. Bump `plugins/sefi-core/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` together, as the 0.4.1 change did.
- [x] 10. Run `bash plugins/sefi-core/scripts/ci/run-all.sh` in full. (needs: 9)
  Paste the real tail into the final report. A run that was not executed is PENDING, never
  assumed. `validate-loops.sh` should pass unchanged -- these three workflows are additive and
  not referenced by any `loops/*.loop.md` `cloud:` declaration, so the existence check has
  nothing new to enforce against them.
- [x] 11. Commit on a feature branch, push, open a PR. Do not merge. (needs: 10)
  DONE (2026-08-24): commit a8d8408 on branch plan/opencode-workflows, pushed; PR
  https://github.com/xsefirosus/sefi-agents/pull/3 opened against main, unmerged per
  human-checkpoint.md.
  Follow this repo's own never-auto-merge rule
  (`skills/sefi-orchestration/references/human-checkpoint.md`) -- this is new unattended-spend
  surface even at manual-dispatch-only, and the owner reviews before it lands on `main`.

## Files Touched
.github/workflows/triage-opencode.yml (new); .github/workflows/retro-opencode.yml (new);
.github/workflows/sync-opencode.yml (new); adapters/OPENCODE.md; README.md; CHANGELOG.md;
plugins/sefi-core/.claude-plugin/plugin.json; .claude-plugin/marketplace.json;
state/plan-opencode-workflows.md (this file, steps 1-3's findings recorded in place)

## Requires Tools
bash, npm, git, gh, the `opencode` CLI (installed fresh in step 1 -- not currently present in
this session's environment, confirmed via `which opencode` returning not-found)

## Risks
- The model id and install command are WebSearch-derived, not WebFetch-verified against a
  primary source -- `opencode.ai`, `pi.dev`, and `news.ycombinator.com` all returned
  `EGRESS_BLOCKED`/403 to this planning session. Step 1-2 exist to close this gap with a real
  `npm install` and `opencode models` call before any YAML is written. Do not skip them because
  the id "looks right" from search snippets.
- `Muse Spark 1.2 Contributor Free` trains on submitted prompts/completions per its own terms
  (per the OpenCode announcement snippet found). These three workflows must only ever run
  against this repo's own already-public content -- never adapt them to point at a private or
  client codebase without re-reading that tradeoff.
- These three workflows are additive alongside the already-scheduled Claude-based
  `triage.yml`/`retro.yml`/`sync.yml`. Manual-dispatch-only is this plan's mitigation, not a
  guarantee: a human who dispatches an OpenCode run at the same time a scheduled Claude run is
  mid-cycle on the same loop still hits the untested Parallel Collision failure mode
  (`docs/LOOP-FAILURE-MODES.md` S3) -- the `acting_on` lock is the only defense and has never
  run live even for the Claude-only case.
- If step 3 finds the free tier requires a credential, that secret does not exist in this
  repo's Actions settings yet and must be added by the owner before first run -- same
  prerequisite-not-satisfiable-from-inside-the-repo shape as `ANTHROPIC_API_KEY` already is for
  the Claude-based workflows.
- Step 3 resolution: the repo owner must add `OPENCODE_ZEN_API_KEY` under Settings >
  Secrets > Actions before first manual dispatch -- the workflows construct
  `$HOME/.local/share/opencode/auth.json` from it at runtime because no CLI env-var
  contract for the Zen key could be verified from primary sources.
- No prior note in `memory/decisions/` constrains this plan (not re-checked by this planning
  pass; re-check before step 11 in case a decision landed since).
- Step 10 result (2026-08-24): bash plugins/sefi-core/scripts/ci/run-all.sh ran in full;
  test-integration OK (33 passed); validate-* all OK; test-scripts 2 failed / 144 passed
  -- BOTH failures reproduced identically on pristine origin/main (verified by stash-run),
  so they are pre-existing and outside this plan's scope: (1) resolve-shared-memory-path.sh
  'cross_project_enabled: false' case expects exit 1, got 0; (2) hooks.json quote-wrap
  assertion needs jq, absent on this Windows machine. No regression introduced by this
  branch; Done Criterion "run-all.sh exits 0" is unsatisfiable on any branch until those
  two ship fixes.

## Done Criteria
Steps 1-3 each have a recorded, tool-confirmed answer in this file (not left as the
WebSearch-derived guess above). `bash plugins/sefi-core/scripts/ci/run-all.sh` exits 0.
`.github/workflows/` contains three new `*-opencode.yml` files, each verified by grep to have
NO active `schedule:` block and to invoke the step-2-confirmed model id verbatim (not a
placeholder or a different id). `adapters/OPENCODE.md` and the README harness table both
mention the new workflows. A PR is open against `main`, unmerged, per the never-auto-merge
rule.
