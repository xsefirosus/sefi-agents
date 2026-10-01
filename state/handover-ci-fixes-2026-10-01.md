# Handover: CI-red fixes for the v0.9.5 Systems Audit (no 0.9.6)

## Goal
Finish verifying the four hosted-CI failures fixed for the already-published v0.9.5 Systems Audit skill. There is NO 0.9.6: v0.9.5 (tag v0.9.5, release published 2026-09-30) stands, and none of these changes moves a tracked version surface, so no version bump exists.

## Starting state
Branch fix/ci-validate-failures, cut from origin/main at the v0.9.5 merge. Seven files changed, all reviewed: personal-path fixture rewording, token-budget trims, Hermes quarantine test, sandbox transient-attributes restore. Green by execution on a symlink-less host: personal-paths, token budget 10877/10880, sandbox unset, scorecard, runner, behavior, routing plus CRLF guard, doc-counts 17/20/13/3, orphans, release-strict.

## What is PENDING (your jobs, in order)
1. Run test-systems-audit-installers.sh to completion on a symlink-capable Linux host or Docker. Prior partial: 15/0 observed single-read, 29/0/13 mid-run. Symlink legs PENDING here only for lack of privilege.
2. Prove Hermes guard-discrimination live: remove the is_symlink pre-check in a temp copy and confirm the runtime-copy test FAILs, then restore.
3. Run test-audit-integration.sh to completion and confirm exit 0.
4. If all green, open a PR of this branch to main for human review. Do NOT merge, tag, or release without explicit human approval.

## What NOT to do
No 0.9.6 tag or release under any circumstance. Never move v0.9.3 or v0.9.4 tags. Never commit the dirty D:\Project tree or its sefi-agents/ subdirectory. Never claim a PASS for unexecuted work.
