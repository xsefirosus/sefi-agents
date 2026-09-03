# Release surfaces

Ported from the `track-astral-releases` skill of `Demonbane18/astral-orchestrator` (MIT)
-- its release-surfaces reference and `release-ledger.py` -- adapted to sefi-agents' six
surfaces. Read this before checking or recording any surface.

## Evidence order

Prefer direct, current evidence in this order:

1. The public surface itself.
2. The provider's official CLI or API (`gh`, `git ls-remote`).
3. A repository artifact or local command that proves only the local state
   (`git tag --points-at HEAD`, a `file:line` read).
4. Prose documentation, which never overrides a manifest or a public page.

Do not infer one surface from another. If `git` or `gh` fails or returns nothing,
record the surface as `unobserved`, never a guessed value.

## Surface contracts

| Surface token | Final state | Sufficient evidence | Common false proof |
|---|---|---|---|
| `plugin.json` | version string matches the target | `version` field read at `file:line` in `plugins/sefi-core/.claude-plugin/plugin.json` | A README skill/agent count, or a CHANGELOG heading, that happens to agree |
| `marketplace.json` | BOTH `metadata.version` and `plugins[0].version` match | both occurrences read at `file:line` in root `.claude-plugin/marketplace.json` | Updating one occurrence and assuming the second one followed |
| `changelog` | first *versioned* `## [x.y.z] - DATE` heading matches -- a non-semver heading such as `## [Unreleased]` is skipped, the first semver-shaped heading is the surface | the heading line read at `file:line` in `CHANGELOG.md` | A `### Added` bullet with no dated heading above it; an `## [Unreleased]` heading read as the release |
| `git-tag` | `v<version>` points at the release commit locally AND on `origin` | `git tag --points-at HEAD` and `git ls-remote --tags origin` output | A local tag that was never pushed to `origin` |
| `github-release` | a published (non-draft) GitHub release for `v<version>` | `gh release view v<version>` showing the tag, date, and notes | A local or pushed tag with no release; a draft release |
| `github-marketplace-index` | the public `marketplace.json` at the documented ref shows the target version | `gh api repos/<owner>/<repo>/contents/.claude-plugin/marketplace.json` (raw) parsed for `version` | Install commands quoted in a README; a preview/branch ref instead of the documented one |

## Status vocabulary

- `match` -- the surface shows the target version with its final evidence.
- `lag` -- the surface still shows the previous version; the bump has not reached it yet.
- `mismatch` -- the surface shows a version that is neither the target nor an orderly
  previous release (for example a tag pushed ahead of the `plugin.json` bump). This is
  drift: report it, do not silence it by editing the ledger.
- `unobserved` -- not checked this session, or the tool to check it failed / returned
  nothing.

## Recording rules

- Append one row per surface per observation; never edit or delete a prior row.
- Every row carries the exact command output or `file:line` in its `evidence` column and
  an RFC 3339 UTC (`Z`) timestamp in `observed-at`.
- Add a `mismatch` or `lag` row without removing the row it supersedes -- the lag history
  is the point of the ledger.
- Say `partially released`, not `released`, until every surface is `match`.

## Handoff

When reporting release state, always include:

- the target version and its source commit;
- each surface's latest observed version, status, and evidence;
- the GitHub release URL and the marketplace ref when observed;
- every remaining lag or human-confirmation gate, with the next action for each.
