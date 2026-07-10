# Changelog

All notable changes to sefi-agents are documented here. Format follows Keep a
Changelog; this project adheres to Semantic Versioning.

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
  gen-router, plus a nine-validator CI suite under `scripts/ci/`.
- Project templates copied by `/sefi:init`: memory vault, state ledger,
  inbox, two loop specs, config (sefi + budget), GitHub Actions workflow.
- Adapters for Hermes Agent, OpenCode, and Codex.
- Docs: LOOPS, ANTIPATTERNS, CHECKLIST, BUDGET, OPTIONAL-TOOLS.
- `install.sh` (human fallback) and `Install.md` (agent-targeted bootstrap).

[0.1.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.1.0
