# Changelog

All notable changes to sefi-agents are documented here. Format follows Keep a
Changelog; this project adheres to Semantic Versioning.

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
