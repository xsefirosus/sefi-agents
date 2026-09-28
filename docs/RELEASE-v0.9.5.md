# v0.9.5 Release Notes

v0.9.5 adds Systems Audit for on-demand, evidence-based reviews of Sefi department
outputs. On Claude Code or OpenCode, run `/sefi:audit build`; in Codex, use
`Use $systems-audit for the build scope`; in Hermes, ask
`Run the systems-audit skill for the build scope.` Each form selects one supported scope
and creates an ignored-local report under `audits/`. The audit records its scope, evidence,
limitations, and capped findings; it asks for clarification when the scope is missing or
unsupported.

## Audit workflow

Systems Audit accepts `complete`, `research`, `product`, `design`, `build`, `quality`,
`docs`, and `delivery`. The top-level orchestrator owns dispatch; the `systems-audit` skill
supplies the evidence method; and `systems-auditor` writes the report without dispatching
another agent or modifying source. The `complete` scope reviews all departments in their
defined order while reporting sampling and limitations. The report keeps findings separate
from proposed remedies and uses `INCOMPLETE` when a required artifact cannot be read or the
report cannot be written.

## Installed runtime

The Claude Code, Codex, OpenCode, and Hermes installers package the audit skill, its
references, the Systems Auditor, and the report-validation runtime. Installed audit
invocations resolve the runtime root separately from the audited project root, so report
path validation stays within the selected project. Reports use
`audits/audit-report-<scope>-<timestamp>-<session>.md`; local memory search and
`/sefi:memory-index rebuild` include them, while cross-project memory mirroring refuses
them.
