# Changelog

All notable changes to sefi-agents are documented here. Format follows Keep a
Changelog; this project adheres to Semantic Versioning.

## [0.2.6] - 2026-08-11

The agent files themselves. The three preceding releases built gates and mechanisms around
the roster and barely touched the roster: 2 of 13 agents got a behavioral change, and
product-manager -- the planner every other agent consumes -- got only a frontmatter field.
This spends the remaining word budget on that gap. Agents total 7906 -> 8196 words against
a cap of 8320; the cap itself is unchanged, because it is doing real work.

Two themes, both wiring rather than prose polish.

### Fixed -- agents describing mechanisms that changed under them

- `software-engineer` and `qa-engineer` now distinguish a gate TIMEOUT from a red gate.
  Timeout classes shipped in 0.2.3 and neither agent was told: exit 124 is a measurement
  that never finished, not a failure. The software-engineer must narrow the slice or raise
  the budget rather than report a test failure; the qa-engineer must treat it as evidence
  for NEITHER verdict, the same category as `gate.sh`'s "no known toolchain detected"
  (which qa-engineer.md item 2 already handled, and which timeouts belong beside).
- `devops-engineer` owns budget plumbing and did not know `budget-check.sh` grew exit 3.
  CANNOT MEASURE is not EXCEEDED and is certainly not a pass -- and papering over it with
  `--spent 0` re-opens the fail-open that 0.2.3 closed, so the agent now says so.
- `support-engineer` runs the morning-triage Discovery move and did not know
  `probe-tools.sh` exists. It now probes first and triages at STATED REDUCED SCOPE when a
  tool is BROKEN or MISSING, which is the whole point of having built the probe.

### Added -- the plan gains the fields three other agents were guessing at

`product-manager` writes the artifact the engineering-manager, software-engineer and
qa-engineer all consume. Three things it knew and never wrote down:

- **Slice sizing.** The software-engineer builds "exactly one plan slice" and nothing
  defined how big a slice may be, while `budget.yml` caps a dispatch at $0.15 with
  `max_retries: 2`. The planner authors the work those caps must hold and had never been
  told they exist, so an oversized slice was a planning failure that surfaced much later as
  a budget breach. Steps are now sized to fit one dispatch; a step that cannot is two steps.
- **Dependency markers.** The engineering-manager's protocol says "sequence, do not
  parallel-guess" -- but a flat checkbox list gave it nothing to sequence FROM, so
  `max_parallel_worktrees: 3` was unusable without guessing which steps were independent.
  Every step now ends with `(needs: <numbers>)` or `(needs: -)`, and the
  engineering-manager sequences from those markers rather than intuition.
- **Tool declaration.** Loops declare `requires-tools:` and get probed; a plan whose steps
  shell out to `gh` or `docker` declared nothing, so the probe could not cover it. Plans
  now carry `## Requires Tools`, with `none` as a deliberate declaration rather than a
  blank.

`validate-plan-structure.sh` enforces all three, so they are gates rather than suggestions.
A regression test asserts the product-manager's own worked example passes that validator --
an agent that teaches a format its gate rejects trains every plan into a failure, and a
small model matches structure from the example far more than from the prose.

test-scripts: 51 -> 54.

## [0.2.5] - 2026-08-11

Model identifiers verified against the web rather than assumed, and a reasoning-effort dial
added to the map. The placeholder ids shipped in 0.2.4 were labelled unverified; this
replaces them with checked ones and revises one tier assignment on the evidence.

### Changed

- Codex now maps to the GPT-5.6 family, which turns out to be a three-model line that fits
  the tiers exactly: `gpt-5.6-sol` (flagship) / `gpt-5.6-terra` (balanced workhorse) /
  `gpt-5.6-luna` (fast, cheap) -- "Terra as default, Sol for the hard parts, Luna for
  volume". 0.2.4 shipped terra on `high` and luna on `mid` with an unverified `5.5-gpt` on
  `low`. Sol on `high` is the better fit: the high tier is the adversarial judge, and it
  should be the strongest model available, not the middle one. Also corrected the prefix --
  the real ids carry `gpt-`, so `5.6-terra` would not have resolved.
- Noted a deadline that affects anyone still on the old line: `gpt-5.4` and `gpt-5.4-mini`
  retire from Codex on 2026-08-31, replaced by `gpt-5.6-terra` and `gpt-5.6-luna`.
- OpenCode and Hermes confirmed on `deepseek-v4-flash-free` (200K context, 128K output,
  free tier). The name in 0.2.4's opencode row was shortened; both rows now carry the full
  identifier. The free-window training caveat is confirmed and repeated in the map itself,
  not only in the Hermes adapter.

### Added

- Reasoning effort is now part of the map, as `<tier>_reasoning` beside each `<tier>`, and
  scales with tier on purpose: the high tier is both the adversarial judge and the long
  agent loop, which is exactly where more reasoning pays for itself.
  - Codex `model_reasoning_effort` accepts minimal|low|medium|high|xhigh -> xhigh/high/medium.
  - OpenCode and Hermes (DeepSeek V4 Flash) support high and max, with the documented
    guidance "high for quick edits, max for long agent loops" -> max/high/medium. A loop
    cycle is a long agent loop.
  - Claude Code exposes no per-agent reasoning dial, so its rows read `none` -- stated
    rather than left blank, so a missing value is never mistaken for an unset one.
- `model-for.sh --reasoning` resolves the effort for a tier, so installers and validators
  read it the same single way they already read the model.
- `install-opencode.sh` writes `options.reasoningEffort` into each converted agent. Written
  per agent rather than assumed, because some OpenCode versions exclude DeepSeek models
  from the reasoning-effort system entirely.
- `apply-model-map.sh` prints the matching `~/.codex/config.toml` block. Reasoning is
  deliberately NOT written into Codex frontmatter: Codex reads it from config.toml, so an
  agent-file field would be inert while looking wired -- the exact shape of the inert-config
  problem `validate-config-wired.sh` exists to catch.
- `validate-model-map.sh` now requires every tier to resolve a reasoning effort on every
  harness, and rejects any value outside none|minimal|low|medium|high|xhigh.

### Caveats kept explicit

`xhigh` is only available on top-tier (codex-max) coding models. It is set on
`codex.high_reasoning` because the request was for the maximum applicable, but if a dispatch
on `gpt-5.6-sol` rejects or silently ignores it, lowering that one value to `high` is the
whole fix -- which is what a single-table map is for.

OpenCode and Hermes still map all three tiers to one model, so `validate-model-map.sh`
continues to warn that generator/evaluator separation is instructions-only there. That is
an honest constraint of a single-model free window, not a defect, and it resolves the day a
second model is available.

## [0.2.4] - 2026-08-11

Model tiers become harness-neutral, and the triage loop gets a scheduler it can actually
run from. Both close gaps found while answering two direct questions rather than by audit.

### Added

- `config/model-map.yml` -- the one place a model identifier is written down. Agents now
  declare a harness-neutral `tier:` (high / mid / low); the map turns that into a concrete
  model per harness. Adding a model, renaming one, or supporting a new harness is an edit
  to one table instead of a pass over 13 agent files. `scripts/model-for.sh` is the single
  reader, so every installer and validator resolves a tier identically.
- `scripts/apply-model-map.sh` for harnesses whose install path reads agent files directly
  with no transform step (Codex via the marketplace). Those installers cannot rewrite
  anything, so the frontmatter has to be right before it is read.
- `.github/workflows/triage.yml`, installed at last -- MANUAL TRIGGER ONLY, with the cron
  line present and commented out. The loop spec had declared `cloud: cron 0 6 * * * via
  .github/workflows/triage.yml` since the dogfooding scaffold, for a file that was never
  copied (the `/sefi:init` step is gated on user confirmation, and none was given -- see
  commit 11346f9, which recorded that correctly). Nothing surfaced the gap afterwards, and
  it deadlocked the whole feedback apparatus: no scheduler means no cycle, no cycle means
  no qa-engineer verdict, no verdict means `state/metrics.md` stays empty, an empty
  scorecard means `retro-improve` can never select a target, and so the flip condition on
  `improvement.enabled` ("once weekly-retro has run a few cycles") was unreachable by
  construction. Manual dispatch breaks the deadlock and produces the first real verdicts
  without committing to unattended spend on a mechanism nobody has watched run.
- `validate-model-map.sh`: every agent declares a tier in {high,mid,low}; every tier
  resolves for every harness in the map; and the literal `model:` matches what the map
  gives for claude-code at that tier. The last check exists because Claude Code reads
  `agents/*.md` straight out of the plugin with no install step, so its model must be
  literally correct on disk while every other harness is rewritten at install time -- two
  fields that can disagree eventually will. It also runs `bash -n` over every shipped
  script: two live syntax errors during this batch came from an apostrophe inside an awk
  comment silently closing the shell single-quote around the awk program, which is
  invisible on reading and instant under `bash -n`.
- `validate-loops.sh` now checks that a project loop naming a cloud workflow names one that
  exists -- the exact gap above, so it cannot recur silently.

### Fixed

- `install-opencode.sh` stripped `model:` entirely, and that quietly cost more than it
  saved. Dropping the field (v0.2.2) was the right call against a hard crash -- OpenCode
  resolves `model: sonnet` as a real provider id and fails -- but it left every agent
  inheriting one session model, so the qa-engineer judged the software-engineer on the
  IDENTICAL model. Generator/evaluator separation, this repo's first design principle,
  silently degraded to instructions-only, and the routing table's "different model where
  possible" was never possible there. The installer now writes the mapped OpenCode model
  instead of deleting the field: the crash stays fixed and the separation comes back.
- `install-hermes.sh` and the Codex path had no model handling at all. Hermes resolves
  tiers at dispatch time (it takes its model from the global `provider.model` and treats
  per-agent `model:` as advisory), so the adapter now documents resolving a tier into the
  `delegate_task` payload rather than pretending an installer does it.

### Notes on the shipped identifiers

The `claude-code` row is verified -- those are the aliases Claude Code itself accepts. The
`codex` and `opencode` rows are user-supplied and have NOT been checked against any
provider's API from this repo, which has no way to check them offline; they are labelled
as such in the map rather than implied to be confirmed. The `hermes` row uses
`deepseek-v4-flash-free`, this repo's own documented Hermes model from
`adapters/HERMES.md`, in preference to a shortened name. A wrong identifier is a one-line
fix by construction, which is the point of the map.

`validate-model-map.sh` warns, without failing, that `opencode` and `hermes` currently map
`high` and `mid` to the same model. On a single-model free window that is an honest
constraint rather than a mistake -- but it does mean the judge and the judged share a
model there. Pointing `high` at a stronger model is what restores a real adversary.

## [0.2.3] - 2026-08-11

A full-repo audit, and the batch of fixes it produced. Nine findings, all first-party.
The pattern across them is worth stating: almost every defect was in the executable layer,
and most were mechanisms this repo had already written down and not built -- or built and
left reachable by prose. Two are second occurrences of a bug class already fixed once
elsewhere, which is the argument for each landing as an executed regression test rather
than a corrected sentence. `test-scripts.sh`: 7 assertions -> 49.

### Fixed

- `budget-check.sh` failed open a second time. v0.2.1 closed the "no ccusage" branch; the
  "ccusage present but broken" branch stayed open. A crash, an empty result, or a `null`
  was assigned straight to `spent`, and `awk -v s="null" '{print s+0}'` is `0` -- so an
  unreadable ledger certified every cap as within budget. Figures are now validated before
  any arithmetic touches them. Exit codes separate EXCEEDED (1) from CANNOT MEASURE (3):
  under `set -e` a crashing `ccusage` previously aborted with a bare exit 1, which no
  caller could tell from a real overrun.
- `gate.sh` enforced no timeout of any kind, while `loop-engineering/SKILL.md` shipped
  per-operation timeout classes as a predecessor-earned rule ("a 300s default killed a live
  12-task dispatch"). A hung suite hung the loop forever -- the same shape as the browser
  tool that ate a 50-iteration retry budget. Two classes now ship (default 300s, test
  900s), expiry is named rather than surfacing as a bare exit 124, and a missing `timeout`
  binary is announced instead of implying a bound that is not enforced.
- `gate.sh` also: `npm test --silent` passed `--silent` to the test script rather than the
  runner; `shellcheck` globbed `./*.sh` unquoted and top-level only, so this repo's own 20
  scripts were never linted by its own gate. Added pnpm/yarn/bun detection, a typecheck
  step, `go vet`, `cargo fmt`, and a Makefile fallback.
- `compress-output.sh` could report a failure with zero diagnostics. Output was filtered to
  lines matching `error|fail|exception`, so a tool failing with "2 tests did not pass"
  printed a FAIL line, a log pointer, and nothing else -- leaving the qa-engineer, the one
  agent meant to read it, with no diagnostic. Falls back to the output tail; a genuinely
  silent failure is labelled as such.
- `inject-memory.sh` injected the head of `index.md` rather than the router. The
  `GENERATED:router` block starts at line 21 of the shipped template, so `head -n 40` spent
  roughly half the 1500-char cap re-sending frontmatter, the title and the folder list every
  session, then truncated the routing lines carrying the only signal. `gen-router.sh`'s
  durability ordering (v0.2.1) only pays off once the window holds router lines at all.
  Falls back to the old window when markers are absent; an initialized-but-empty vault now
  says so in one line instead of injecting a page about nothing.
- The five-move loop gate was satisfiable by prose. `grep -q Discovery` matches the word
  anywhere in the file, so a spec with no section for any move passed the validator whose
  entire purpose is rejecting exactly that. Anchored to the `## <Move>` heading in both
  `validate-loops.sh` and `loop-readiness.sh`; a prose-only spec drops from 80/100 to
  40/100. `validate-loops.sh` now also checks the project's own `loops/`, which this repo
  dogfoods and CI had never looked at.

### Added

- `scripts/probe-tools.sh`, and with it a claim the README had been making without an
  implementation: "tools are probed before a loop may grant them". No probe existed
  anywhere in the repo. The claim was also unbuildable as written -- agent `tools:`
  frontmatter is granted by the harness, not by a loop -- so the mechanism was scoped to
  what is real (external commands a loop's moves shell out to) and the README rewritten to
  describe it. Loop specs now declare `requires-tools:`, `validate-loops.sh` requires the
  line, and the probe reports four states rather than two: presence is not health, and a
  binary that is installed and broken passes `command -v` while failing the work. Offline
  by default; `--deep` opts in to credential checks. This repo's own first live triage lost
  two of six findings to a missing `gh` and only discovered it mid-cycle.
- `scripts/check-handoff.sh`, closing the asymmetry between plans and handoffs. Plans had
  `validate-plan-structure.sh`; the handoff rule -- name the upstream file, inline all
  context, pin the absolute output path -- was enforced by nothing, despite being the more
  expensive failure. A dispatch with a relative `writes:` path resolves against whatever
  working directory the agent inherits, which is how a predecessor's task wrote to the
  user's home directory and a reviewer approved the empty folder it was pointed at. The
  gate blocks a relative path, an empty `reads:` or `context:`, a back-reference such as
  "as discussed above", and an agent slug that resolves to no file.
- `state/retro-ledger.md` and the reversibility half of self-improvement. The retro loop
  could apply bounded, qa-verified edits but had no memory of them: it could re-edit the
  same file every week, re-propose something a human had already rejected, or leave an edit
  in place indefinitely after it made things worse. The ledger is written at edit time
  (the `before` value and the evidence pointer exist only then) and carries the commit SHA
  that makes an edit revertible at all. Three read rules bind before any target is
  selected -- churn guard, rejection memory, evidence debt. The revert threshold is fixed
  now, deliberately, while `state/metrics.md` is still empty: a threshold written after the
  numbers arrive is a threshold fitted to them. A detected regression becomes an `inbox/`
  proposal naming the exact `git revert <sha>`, never an automatic commit.
- `references/close-out.md`, and with it the memory vault's missing producer. `close_out`
  was declared in every loop spec and defined nowhere, while `goal_intake` had a reference
  file. The consequence was structural: `knowledge-manager.md` read `memory/daily/*.md` as
  "the raw material" and distilled it weekly, all twelve other agents filed observations as
  "a candidate for the knowledge-manager", and no agent, hook or command ever wrote a daily
  note. `/sefi:init` created `memory/daily/` and it stayed empty, so the weekly distill was
  a permanent no-op and SessionStart had nothing to inject. `close_out` now dispatches the
  knowledge-manager to file a cycle's durable observations -- or to log SKIP when there are
  none, never neither. It stays an agent dispatch rather than a `Stop` hook because the
  memory-protocol privacy filter has to run first, and a deterministic hook cannot judge
  which bytes are a credential. It produces `tier: trace` notes only; promotion stays the
  weekly recurrence-based job, so the ladder still earns each rung from evidence.

## [0.2.2] - 2026-07-19

Hotfix: a real user running sefi-agents on OpenCode for the first time hit a hard failure
on every single subagent dispatch. First bug this project has had reported from actual
field usage rather than internal audit or testing.

### Fixed

- `install-opencode.sh` preserved every agent's `model:` line verbatim (e.g.
  `model: sonnet`) when converting for OpenCode. OpenCode does not treat this as an
  advisory hint the way Claude Code treats "sonnet" as a native alias -- it tries to
  resolve the value as a real provider/model identifier and fails hard:
  `Model not found: sonnet/`. Every one of the 13 agents carries a `model:` line, so this
  broke every subagent dispatch on OpenCode, not one. `model:` is now dropped entirely
  during conversion, so OpenCode falls back to the session's actual configured model.
- Observed alongside the bug, worth naming even though it is not this repo's own defect:
  when the specialized-agent dispatch failed, the orchestrating model did not stop and
  surface the error -- it silently fell back to an unconstrained generic subagent with
  none of the specialized agent's tool whitelist, output contract, or gate requirement.
  `adapters/OPENCODE.md`'s troubleshooting section now names this as a second problem
  worth stopping for, separate from the root-cause fix above.

### Added

- A regression test in `test-scripts.sh`: runs `install-opencode.sh` end-to-end against a
  temp destination and asserts `model:` is absent from the converted output while every
  other frontmatter field (tools/permission conversion, description, keywords) survives
  intact.

## [0.2.1] - 2026-07-16

Trust-bug batch: a behavioral audit found 11 cases where the repo stated a guarantee its
code did not deliver. All 11 closed, each independently reviewed (spec + quality, 0
Critical/Important), plus a final whole-branch review confirming cross-commit consistency
(also 0 Critical/Important; Ready to merge: Yes).

### Fixed

- `budget-check.sh` was fail-open: with no `ccusage` and no explicit `--spent`, it silently
  treated unmeasured spend as zero, so the shipped `triage.yml`'s "Enforce budget caps" step
  always passed regardless of actual spend. Now exits nonzero when there is no spend
  source; an explicit `--spent 0` remains a valid claim.
- `gen-router.sh` sorted all vault notes alphabetically, so `daily/` (trace notes) always
  preceded `decisions/` (durable notes); since the injection that reads this router
  truncates after ~16 lines, decisions were being silently evicted. Now emits notes in
  durability order (decisions -> entities -> projects -> other -> daily last).
- Six shipped agent/skill files contained references to other files that resolved to
  nothing (e.g. `ui-ux-designer.md`, `anti-hallucination/SKILL.md`, `retro-improve/SKILL.md`
  pointing at paths one directory short of the real file). All six fixed.
- `retro-improve`'s single-writer invariant held only within one project: a shared,
  user-global install let one project's self-improvement loop silently rewrite an agent
  file another project also loads. `/sefi:init` now asks whether an install is shared and
  defaults `improvement.enabled: false` (propose-only, not learning-off) when it is, or
  when the run is non-interactive.
- The `acting_on` loop-coordination lock was check-then-act (grep, then open a worktree),
  so two loops starting near-simultaneously could both find nothing claimed and both
  proceed. Now the claim is committed before the worktree opens, with git push rejection as
  the arbiter. Also: a crashed run's stale claim is now documented as clearable on resume,
  and a `git status --porcelain` preflight now runs before building.
- Three harness adapters (Hermes, OpenCode, Codex) implied or didn't clarify that
  `install.sh` never installs hooks -- so SessionStart memory injection only works via the
  Claude Code plugin path. One adapter's troubleshooting text actively implied a hook
  existed where none does. All three corrected.
- Five declared config keys were never read by any script or named as a rule:
  `memory.vault_dir`, `memory.inject_char_cap` (now both genuinely wired);
  `memory.prune_trace_after_days` (now a report-only threshold for the knowledge-manager,
  no auto-deleter); `per_agent_return_tokens` (now named in sefi-orchestration's
  output-contract rule); `loops.never_auto_merge` (deleted -- its name implied auto-merge
  was a toggle, contradicting the absolute rule in `human-checkpoint.md`, which is
  unchanged).
- `qa-engineer.md` now explicitly distinguishes `gate.sh`'s "no known toolchain detected"
  pass from a real "PASSED (N checks)" pass -- the former means nothing was checked, not
  that something was checked and passed, and must never be accepted alone as sufficient
  evidence for a slice that should have had a real toolchain.
- Three agents (`devops-engineer`, `qa-engineer`, `technical-writer`) had an Escalation
  clause with no time bound at all. All 13 agents now use the same explicit bound ("within
  2 minutes or this turn, whichever is sooner") the other 10 already used.

### Added

- `retro-improve/SKILL.md` now names a recurring routing-table miss as an explicit
  scorecard input, alongside qa-engineer REJECTs, gate failures, and contradictions.

- `validate-config-wired.sh`: CI gate asserting every declared config key is read by a
  script or named as a rule, checked over git-tracked files only.
- `validate-links.sh`: CI gate asserting every repo-path reference in shipped markdown
  resolves -- the reverse direction of the existing orphan-file check, which can only
  catch unwired files, never dangling references.
- `test-scripts.sh`: regression suite for the two behavior-changing fixes above, one
  assertion per audited failure mode plus the paths that must not regress.

## [0.2.0] - 2026-07-11

The software-company release: the roster becomes a 13-agent engineering org, five new
craft/gate skills land (including the cross-cutting anti-hallucination rule), and the
README is rewritten for the public launch.

### Added

- Agents (6 new): engineering-manager, devops-engineer, security-engineer,
  technical-writer, support-engineer, ui-ux-designer.
- Skills (5 new): anti-hallucination (the canonical no-invention rule every agent and
  skill points to), security-review (+ references/security-checklist.md),
  frontend-design (+ references/anti-slop-checklist.md), backend-design
  (+ references/api-checklist.md), technical-writing.
- Full-stack protocol in the software-engineer: vertical slices, contract-first at the
  API seam, backend-design below the seam, frontend-design above it.
- CI checks: validate-agents.sh and validate-skills.sh now require the
  anti-hallucination pointer line in every agent and skill.
- Repository CI workflow (.github/workflows/ci.yml) running the full validator suite on
  every push and pull request.

### Changed

- Roster renamed to software-company roles: researcher -> research-analyst, planner ->
  product-manager, implementer -> software-engineer, evaluator -> qa-engineer,
  librarian -> knowledge-manager, automation-architect -> solutions-architect
  (quant-analyst unchanged). All cross-references updated (routing table, roster,
  loops, docs, templates).
- validate-token-budget.sh: the agents/ word cap now scales with roster size
  (agent_count x 640) instead of the fixed 4,500.
- README rewritten as the public-launch page: evidence-first pitch, generic comparison
  with explicit edges, 13-agent / 12-skill tour, FAQ, and a no-invented-numbers
  commitment.

## [0.1.0] - 2026-07-11

Initial release: loop-engineered multi-agent plugin for Claude Code (also runs
on Hermes Agent, OpenCode, and Codex).

### Added

- `sefi-core` plugin: marketplace + plugin manifests.
- Agent roster (7): researcher, planner, implementer, evaluator, librarian,
  automation-architect, quant-analyst.
- Skills (7): sefi-orchestration, memory-protocol, loop-engineering,
  retro-improve, terse-mode, n8n-workflow-design, strategy-gate.
- Commands (5): init, triage, retro, status, loop-new.
- SessionStart hook that injects the memory router.
- Shell scripts: gate, compress-output, inject-memory, budget-check,
  gen-router, plus eight validators and their run-all entry point under `scripts/ci/`.
- Project templates copied by `/sefi:init`: memory vault, state ledger,
  inbox, two loop specs, config (sefi + budget), GitHub Actions workflow.
- Adapters for Hermes Agent, OpenCode, and Codex.
- Docs: LOOPS, ANTIPATTERNS, CHECKLIST, BUDGET, OPTIONAL-TOOLS.
- `install.sh` (human fallback) and `Install.md` (agent-targeted bootstrap).

[0.2.2]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.2
[0.2.1]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.1
[0.2.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.0
[0.1.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.1.0
