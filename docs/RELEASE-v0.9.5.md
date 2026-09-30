# v0.9.5 Release Notes

v0.9.5 adds Systems Audit for on-demand, evidence-based reviews of Sefi department
outputs. On Claude Code or OpenCode, run `/sefi:audit build`; in Codex, use
`Use $systems-audit for the build scope`; in Hermes, ask
`Run the systems-audit skill for the build scope.` Each form selects one supported scope
and creates an ignored-local report under `audits/`. The audit records its scope, evidence,
limitations, and capped findings; it asks for clarification when the scope is missing or
unsupported.

It runs on demand only. No shipped loop and no scheduled workflow invokes it, and the
command file forbids a scheduled or CI trigger from calling it; each of the three shipped
and three template loop specs records that `audits/` is never scanned on a schedule.

## Audit workflow

Systems Audit accepts `complete`, `research`, `product`, `design`, `build`, `quality`,
`docs`, and `delivery`. The top-level orchestrator owns dispatch; the `systems-audit` skill
supplies the evidence method; and `systems-auditor` writes the report without dispatching
another agent or modifying source. The `complete` scope reviews all departments in their
defined order while reporting sampling and limitations. The report keeps findings separate
from proposed remedies and uses `INCOMPLETE` when a required artifact cannot be read or the
report cannot be written.

Two refusals bound the write: an already existing report path returns
`REFUSED-OVERWRITE` with the file untouched, so a follow-up audit is a new timestamped
file; and a report path that resolves outside the audited project's own `audits/` directory
is rejected before anything is written.

## Installed runtime

The Claude Code, Codex, OpenCode, and Hermes installers package the audit skill, its
references, the Systems Auditor, and the report-validation runtime. Installed audit
invocations resolve the runtime root separately from the audited project root, so report
path validation stays within the selected project. Reports use
`audits/audit-report-<scope>-<timestamp>-<session>.md`; local memory search and
`/sefi:memory-index rebuild` include them, while cross-project memory mirroring refuses
them.

The installers also make their containment rules visible at install time: each resolves its
destination to a physical path before writing and refuses a destination that escapes it,
re-checking containment at each write. Codex additionally refuses a symlinked `AGENTS.md`,
agent profile, marketplace or plugin root, and symlinked content inside the candidate
plugin; Hermes additionally refuses a symlinked skills root, live skill, or managed runtime,
a managed file whose installed path escapes that runtime, and any cleanup target outside
its own quarantine directory. Each refusal names the path and exits non-zero rather than
writing through it.
