---
description: Audit department outputs for one scope through systems-auditor, writing one fenced report without modifying source.
managed-by: sefi-agents
---

# /sefi:audit

Route this command through `systems-auditor`. Usage: `/sefi:audit <scope>`.

Scope = `$ARGUMENTS`, one of `complete, research, product, design, build, quality, docs, delivery`. If empty or outside the allowlist, ask exactly ONE question for the scope -- never assume `complete`, never guess a scope from surrounding conversation just because one is available.

This command is on-demand only and never scheduled: a scheduled or CI trigger must not invoke it, and it sets no `skip_clarification` / `non_interactive` path of its own.

The auditor reviews only the departments in scope against their core checks and sefi-appendix gates (see `docs/AUDIT-DEPARTMENTS.md` for the record), writes exactly one report with the Write tool to `audits/audit-report-<scope>-<timestamp>-<session>.md` -- an ignored-local file under the designated worktree -- and never dispatches subagents, never modifies source, and never fixes what it finds. `complete` audits all seven departments; any other scope audits only its department. Never Edit, never append to an existing report; a follow-up audit is a new timestamped file. The handoff supplies an installed runtime root and designated project root. Before Write, follow the report contract's path-preparation and finding-formatting commands; a `REFUSED-OVERWRITE` outcome ends the audit without altering the existing report. Resolve `<runtime-root>/scripts/ci/validate-audit-report.sh`, then run `--root <designated-project-root> <report-path>`; an inaccessible required artifact or output failure returns `INCOMPLETE`, never `COMPLETE`.

Reply with a short per-department summary plus the report file link only -- never the full findings -- then ask whether to plan fixes and stop for explicit confirmation.
