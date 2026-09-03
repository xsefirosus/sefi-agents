---
tags: [decision, security, git]
type: design-rule
status: active
date-discovered: 2026-09-03
evidence: astral-adoption Phase 4 runner sandbox isolation
scope: all
---

# Trust-Root Leakage: Scan Whole Structure When Hiding Paths

## The Rule

When hiding a path from a co-located process (one that runs in a child environment you control), scan the WHOLE containing structure, not just one named file.

If the process legitimately needs something, place it in a location the process cannot derive from:
- Environment variables
- Argv / stdin
- Current working directory
- VCS metadata (`.git/` files, reflog, branch names)

## Why It Matters

A single carefully-chosen channel (env var, `.git/config`) can re-derive a path you meant to hide, giving the process exactly the same reach as if you had not hidden it at all.

## Evidence From Astral-Adoption Run

**Phase 4 runner**, discovered across four security review passes:

1. **Withdrawn fingerprint design**: put the trust root inside the arm's own git worktree.
2. **`SEFI_ARM_SESSION_FILE` export**: arm's env disclosed `<results-dir>/...`, the path holding `trials.jsonl`.
3. **`git clone` origin metadata** (after above was fixed): sandbox clone left `url = file:///D:/.../<branch>` in `<repo>/.git/config`. The arm's cwd is the repo root, so `cat .git/config` re-derives the path.
4. **Clone reflog** (after remote was removed): same path was still in `<repo>/.git/logs/HEAD` and the branch name in `<repo>/.git/HEAD`.

## Clean Fixes Applied

- Arm scratch in a private `mkdtemp`, never disclosed to the arm process.
- Clone with:
  - `-c core.logallrefupdates=false` (suppress reflog)
  - `checkout --detach` (no branch name in HEAD)
  - `remote remove origin` (no URL in `.git/config`)

## Implementation Notes

- Before declaring a path "hidden", grep the entire containing filesystem tree.
- For VCS, this means every file under `.git/`, not just `.git/config`.
- The attacker is not the arm; it is a decoy input the arm processes or a compromise of the arm's own code. The arm itself can be trusted to not deliberately cheat (if you can't trust it, don't co-locate it).

Related: [[memory/decisions/mandatory-check-must-fail-explicit]]
