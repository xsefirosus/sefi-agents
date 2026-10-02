# Acceptance evidence: v0.9.5 Systems Audit (2026-10-01)

Retrospective corrective evidence for the already-published v0.9.5 Systems Audit
feature. Evidence generated here is current verification, not proof that checks
occurred before publication. Tags/releases are unchanged.

Plan: `state/plan-v095-acceptance-remediation-2026-10-01.md`.
Branch: `handover/v095-acceptance-remediation-20261001` (Step 2 work uncommitted).

## Layout

- `README.md` -- this file.
- `baseline.md` -- target commit, host, and tool versions for the runs.
- `commands.jsonl` -- one JSON object per executed command: UTC time, exact
  command, target commit, tool version, exit code, sanitized log path, artifact
  SHA-256, and PASS/FAIL/PENDING/UNKNOWN.
- `deterministic/` -- sanitized stdout/stderr logs, one per Step 2 command.

## Evidence protocol

Each `commands.jsonl` record carries: `utc`, `command`, `commit`, `tool`,
`exit`, `log`, `sha256`, `verdict`. Verdicts: PASS (exit 0 on Linux with all
required assertions held and no required capability PENDING), FAIL (exit
nonzero or a required assertion failed), PENDING (unfinished measurement,
including timeout exit 124), UNKNOWN (could not determine).

## Step 2 scope

Re-run deterministic acceptance on a symlink-capable Linux host and correct
only demonstrated required failures:

1. `bash plugins/sefi-core/scripts/ci/validate-token-budget.sh`
2. `bash plugins/sefi-core/scripts/ci/test-audit-report-validator.sh`
3. `bash plugins/sefi-core/scripts/ci/test-systems-audit-contract.sh`
4. `bash plugins/sefi-core/scripts/ci/test-systems-audit-behavior.sh`
5. `timeout 900s bash plugins/sefi-core/scripts/ci/test-systems-audit-installers.sh`
6. `timeout 900s bash plugins/sefi-core/scripts/ci/test-audit-integration.sh`

Hermes mutation proof (intact guard PASS, post-copy guard removal FAIL,
restore PASS) is exercised inside disposable copies by suite 5 only; the
fetched tree is never unguarded to manufacture a result.
