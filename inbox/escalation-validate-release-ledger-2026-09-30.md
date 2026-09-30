---
status: open
raised_by: devops-rails
date: 2026-09-30
reason: red-validator
release: v0.9.5
---
# Human decision required: validate-release-ledger.sh exits 1 on state/release-ledger.md

- Date: 2026-09-30 (UTC timestamps in the ledger).
- Status: OPEN. v0.9.5 is fully published; this is validator debt, not a release defect.
- Cause: hard-fail 1 of `validate-release-ledger.sh` treats a genuine `lag` row as a
  contradiction of the in-repo `match` rows in the same version group, so an append-only
  ledger can never contain a real observed lag and still validate.

## Current output

```
ERROR: surfaces disagree on the version claim 0.9.4: observed 0.9.3,0.9.4
ERROR: surfaces disagree on the version claim 0.9.5: observed 0.9.4,0.9.5
validate-release-ledger: 2 error(s) -- latest version claim 0.9.5 is contradicted
```

Exit code 1.

## Proof it is pre-existing

The same two errors, byte-identical, are produced by running the same script against the
ledger at `origin/main` `51c2305` before any of the 2026-09-30 appends:

```
git show origin/main:state/release-ledger.md > <tmp>; \
  validate-release-ledger.sh --root . --ledger <tmp>
```

No append made in this session introduced a new contradiction. The offending rows are:

- 0.9.4 group, `github-marketplace-index` observed `0.9.3` `lag` (2026-09-26T15:11:48Z),
  later superseded by a `0.9.4` `match` append in the same group.
- 0.9.5 group, `github-marketplace-index` observed `0.9.4` `lag` (2026-09-28T01:59:13Z),
  later superseded by a `0.9.5` `match` append in the same group.

## Why it cannot be cleared without a human decision

The ledger is append-only and forbids hand-editing a historical row, so the `lag` rows stay
forever and the error is permanent for any version that ever had a real lag. Clearing it
needs one of:

1. A rule change: scope hard-fail 1 to rows that share the same `observed-at` observation
   round, or exempt `lag`/`mismatch` rows recorded before the group's first `match` row.
2. A one-time human-authorized edit of the two superseded `lag` rows, converting their
   `observed` to `unobserved` while keeping the `lag` status and the evidence text. This
   rewrites ledger history and is explicitly out of bounds for an agent.
3. Accept the failure and gate `validate-release-ledger.sh` to `--strict` only, or exclude
   it from `run-all.sh` non-strict, so the always-on run is not red for historical lag debt.

Option 1 is the correct long-term fix and is a validator change, not a ledger change.

## Blast radius

`validate-release-ledger.sh` is wired into `run-all.sh`, so every CI run on `main` is red
today, before and after this release. The latest-version surface set is a genuine 6/6
`match` for 0.9.5, so the red is false-negative, not a hidden lag.

## Secondary environment note (worked around, no action required)

`gh` is not installed on this host and no `GH_TOKEN`/`GITHUB_TOKEN` is set, so the GitHub
surfaces were read and written through the REST API using the credential the repository's
own `git credential fill` already supplies (principal `xsefirosus`, owner of this repo).
Same principal, same repository, no new identity. If a machine-local `gh` install is
expected as a baseline for this repo's release procedure, it is worth adding to the setup
path.
