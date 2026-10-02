# Handover: CI-red fixes for the v0.9.5 Systems Audit (no 0.9.6)

## Goal
Finish verifying the four hosted-CI failures fixed for the already-published v0.9.5 Systems Audit skill. There is NO 0.9.6: v0.9.5 (tag v0.9.5, release published 2026-09-30) stands, and none of these changes moves a tracked version surface, so no version bump exists.

## Starting state
Branch fix/ci-validate-failures, cut from origin/main at the v0.9.5 merge. Seven files changed, all reviewed: personal-path fixture rewording, token-budget trims, Hermes quarantine test, sandbox transient-attributes restore. Green by execution on a symlink-less host: personal-paths, token budget 10877/10880, sandbox unset, scorecard, runner, behavior, routing plus CRLF guard, doc-counts 17/20/13/3, orphans, release-strict.

## Historical task list at handoff (now complete)
1. Run test-systems-audit-installers.sh to completion on a symlink-capable Linux host or Docker. Prior partial: 15/0 observed single-read, 29/0/13 mid-run. Symlink legs PENDING here only for lack of privilege.
2. Prove Hermes guard-discrimination live: remove the is_symlink pre-check in a temp copy and confirm the runtime-copy test FAILs, then restore.
3. Run test-audit-integration.sh to completion and confirm exit 0.
4. If all green, open a PR of this branch to main for human review. Do NOT merge, tag, or release without explicit human approval.

## What NOT to do
No 0.9.6 tag or release under any circumstance. Never move v0.9.3 or v0.9.4 tags. Never commit the dirty D:\Project tree or its sefi-agents/ subdirectory. Never claim a PASS for unexecuted work.

## Completion record (2026-10-01)

All four handoff jobs are complete against tested code commit `24b82ef14d23b8526c538f8459638ac97a17fe65`.

- The installer suite finished with `231 PASS / 0 FAIL / 0 PENDING`. The original fixture masked the guard because fetched-tree rejection happened before the runtime copy. The new runtime-copy seam guard remained intact: removing only its two lines produced `228 PASS / 3 FAIL / 0 PENDING`, and restoring them produced `231 PASS / 0 FAIL / 0 PENDING`.
- The integration suite exited 0 with `0 BAD / 0 PENDING`.
- Independent QA was PASS. The named prior canonical checks were green. The Codex independent capability probe avoids the false `EEXIST` PENDING result.
- Hosted CI run `36831728058` is SUCCESS for the attested commit: https://github.com/xsefirosus/sefi-agents/actions/runs/36831728058

PR 19 is OPEN and awaits human review and explicit merge approval: https://github.com/xsefirosus/sefi-agents/pull/19. No merge or release was performed.
