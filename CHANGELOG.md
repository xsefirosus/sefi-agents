# Changelog

All notable changes to sefi-agents are documented here. Format follows Keep a
Changelog; this project adheres to Semantic Versioning.

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

[0.2.1]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.1
[0.2.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.0
[0.1.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.1.0
