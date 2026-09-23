# v0.9.2 Release Notes

v0.9.2 adds install version-tracking. Every OpenCode install writes a
`sefi-package-manifest/v1` record (per-file hashes plus `source_version` and
`source_commit`) beside the installed `scripts/` copy, and every Hermes install
records the laid-down source version beside the installed skills. Both
installers accept `--auto-update`, which diffs the installed copy against the
checkout before writing anything and never silently overwrites user edits. The
release remains local-first, offline-testable, and dependency-free.

## Version identity

The recorded version is the source commit's git tag (exact match), never a
guessed release number. An untagged source records `unreleased-plus-<commit>`;
outside a git checkout both values are `UNKNOWN`. Manifests written before
these fields existed read back as `UNKNOWN`. The existing manifest check
behavior is unchanged.

## Diff verdicts

The manifest diff reports one of three verdicts: `current` (installed hashes
and version match the source), `stale` (the source moved on; the message names
the new version and commit), or `drift` (installed files were user-modified;
the message names them).

## Safe re-installs

Re-running either installer with `--auto-update`: `current` exits 0 doing
nothing, `stale` performs the normal install, and `drift` stops with an error
instead of overwriting. OpenCode also accepts an explicit `--force` to
overwrite drifted files deliberately; Hermes asks for a by-hand reconciliation
followed by a reinstall without the flag. Version tracking covers the OpenCode
`scripts/` subtree manifest and the Hermes installed-skills version record;
other subtrees have no hash baseline to diff against.

## Release status

This working tree is partially released for v0.9.2: the in-repo surfaces
(manifests, changelog, ledger) are reconciled, while the tag, GitHub release,
and marketplace index remain unobserved. Local CI and fresh-install fixtures
must pass before a tag, GitHub release, or marketplace update is created.
Publication requires separate, explicit release authorization and evidence.
