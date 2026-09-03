---
tags: [decision, git, safety]
type: design-rule
status: active
date-discovered: 2026-09-03
evidence: astral-adoption Phase 4 shim file reconstruction
scope: all
---

# git checkout Is Unsafe for Uncommitted Changes

## The Rule

To set aside a file and restore it later, use `cp` to a scratch copy.

Never use `git checkout` (with or without `HEAD`) on a file whose changes are not committed.

## Why It Matters

`git checkout -- <path>` on a never-staged file silently restores it from the index, which equals HEAD, destroying all working-tree changes. There is no warning, no prompt, no undo (outside git's reflog, which may expire).

## Evidence From Astral-Adoption Run

**Phase 4 runner hardening**, security review pass 3:

A fix agent ran `git checkout -- <file>` to "restore" a security-reviewed shim that had been edited in earlier rounds. The file had never been staged (working-tree content only). The command silently destroyed 95 lines of security-reviewed code. The agent had to reconstruct it from conversation context, and the loss was discovered only during manual review.

## Safe Pattern

```bash
# To save and restore:
cp path/to/file /tmp/backup-$(date +%s).txt
# ... make changes ...
cp /tmp/backup-*.txt path/to/file  # restore

# Or commit:
git add path/to/file
git commit -m "WIP: trying something"
# ... can now use git checkout or git reset safely
```

## Implementation Notes

- Prefer `cp` for short-term saves.
- When uncertain about a file's stage state, run `git status` first.
- For temporary work, commit early (even if the commit is a WIP and will be amended or reverted later).

Related: [[memory/daily/2026-09-03]] (close-out note for this run)
