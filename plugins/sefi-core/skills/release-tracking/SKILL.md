---
name: release-tracking
description: Use for every version bump, release, tag, or investigation of a mismatched sefi-agents version. Reconciles six independent publication surfaces -- plugin.json, marketplace.json, CHANGELOG, git tag, GitHub release, GitHub marketplace index -- against one append-only evidence ledger, and reports partially released, never released, until every surface matches verbatim.
managed-by: sefi-agents
---

# Release tracking

Maintain one evidence-backed release ledger at `state/release-ledger.md`. Treat every
publication surface as independent: a bumped `plugin.json`, a local git tag, or a drafted
GitHub release does NOT prove the other surfaces changed. Ported from
`Demonbane18/astral-orchestrator`'s `track-astral-releases` skill and its
`release-ledger.py` (MIT): same evidence-priority order, the same "common false proof"
column, and the same strict "say `partially released`, not `released`, until every surface
matches" gate.

All factual output follows the anti-hallucination skill: cite the exact command output or
`file:line` you read, or mark the surface `unobserved`. Never infer one surface from
another, and never guess a surface you did not observe this session.

## The six surfaces

Read [release-surfaces.md](references/release-surfaces.md) before checking or recording
any surface. Each surface is reconciled against the target version resolved from
`plugins/sefi-core/.claude-plugin/plugin.json` -- never from prose.

| # | Surface | Where it lives | Sufficient evidence | Common false proof |
|---|---|---|---|---|
| a | `plugin.json` version | `plugins/sefi-core/.claude-plugin/plugin.json` `version` | The `version` string read at `file:line` | A README count or CHANGELOG heading alone |
| b | `marketplace.json` version | root `.claude-plugin/marketplace.json` -- BOTH `metadata.version` AND `plugins[0].version` (two occurrences) | Both occurrences read at `file:line` | Updating one occurrence and assuming the other followed |
| c | CHANGELOG top entry | `CHANGELOG.md` first *versioned* `## [x.y.z] - DATE` heading -- non-semver headings such as `## [Unreleased]` are skipped, the first semver-shaped heading is the surface | The heading text read at `file:line` | A `### Added` line without its dated heading; an `## [Unreleased]` heading mistaken for the release |
| d | Git tag | `git tag --points-at HEAD`; `git ls-remote --tags origin` | The tag name from the command output | A local tag that was never pushed |
| e | GitHub release | `gh release view v<version>` | The release page / `gh` output showing the tag and metadata | A local tag, or a draft release not yet published |
| f | GitHub marketplace index | the public `marketplace.json` at the documented ref (`gh api repos/<owner>/<repo>/contents/.claude-plugin/marketplace.json`) | The `version` fields in the fetched JSON | Install commands written only in a README |

## Evidence priority order

Prefer direct, current evidence, in this order:

1. The public surface itself (the GitHub release page, the fetched marketplace JSON).
2. The official CLI or API for that surface (`gh`, `git ls-remote`).
3. A local repository artifact or command that proves only local state (`git tag
   --points-at HEAD`, a `file:line` read).
4. Prose documentation, which never overrides a manifest or a public page.

If `git` or `gh` fails or returns nothing for a surface, record that surface as
`unobserved`. Do NOT downgrade it to a guessed value.

## The strict gate

A version is `released` ONLY when all six surfaces carry that exact version with their
final evidence. Until then the status is `partially released` -- state it that way, name
every lagging surface, and give the next action for each. One surface ahead of the others
(for example a pushed git tag whose `plugin.json` bump never landed) is a `mismatch`, not
a release: it is drift, and it is reported, not reconciled by editing the ledger.

`validate-release-ledger.sh` (wired into `run-all.sh`) enforces these hard-fail rules:

1. Within any single version group in the ledger -- not only the latest, since an
   append-only ledger accumulates historical version claims -- two surfaces carry
   contradicting non-`unobserved` `observed` values.
2. A latest-version row's `observed` value contradicts the on-disk source it names
   (`plugin.json`, `marketplace.json`, or the `CHANGELOG.md` first versioned heading).
3. `marketplace.json`'s two version occurrences (`metadata.version` and
   `plugins[0].version`) disagree with each other on disk -- independent of what any
   ledger row observed.

It also exits 1 on a missing ledger, an empty ledger, a missing `--ledger` / `--root`
value, an unrecognized `--opt=value` joined option, an unknown surface or status token, or
a non-empty `version` cell that is not an *exact* semver -- the match is anchored
end-to-end, so a near-miss such as `0.5.2.1`, `0.6.0-rc1`, or `1.2.3.4` is rejected by
name, never silently truncated to a prefix. Both `--ledger PATH` and `--ledger=PATH`
option forms are accepted, and GFM alignment-marker separator rows (`:---`, `---:`) are
skipped like any other table separator.

Any surface `unobserved` for the latest version is a printed WARNING, not a failure.

## Surfaces that are deliberately NOT tracked

The per-harness install configs `opencode.json`, `.codex/config.toml`, and
`install-hermes.sh`'s `SKILLS=` list are EXCLUDED from the surface list: none of them
carries a plugin version string. They are install-transform inputs already gated by
`validate-adapters.sh` and `validate-config-wired.sh`, not published version surfaces.

## The ledger

`state/release-ledger.md` is append-only, with a fixed table grammar:

```
| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
```

- `version` -- the reconciliation target (the `plugin.json` version).
- `expected` -- the version that surface should show for that target.
- `observed` -- the version actually read this session, or `unobserved`.
- `status` -- one of `match`, `lag`, `mismatch`, `unobserved`.
- `evidence` -- the exact command output or `file:line` the `observed` value came from.
- `common-false-proof` -- the weaker signal that must NOT be accepted for this surface.
- `observed-at` -- an RFC 3339 timestamp (UTC `Z`) for when the row was recorded.

Never hand-edit an existing row and never rewrite history to hide a lag: append a new row
when a surface changes. Mirrors the discipline of `state/metrics.md:1`.

## Recording a surface

1. Read the target version from `plugins/sefi-core/.claude-plugin/plugin.json`.
2. Observe each surface with the command in the table above; keep the raw output.
3. Append one row per surface with a fresh `observed-at` timestamp.
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/ci/validate-release-ledger.sh` and read its
   `latest <v>, N/6 surfaces observed, K warning(s)` line.
5. If any surface lags, finish with a matrix of latest observed version, status,
   evidence, and next action per surface. Say `partially released`, not `released`.

## Publication gates

- Ask before pushing a tag, publishing a release, or changing any marketplace listing
  unless that exact action was already authorized.
- Record `github-release` as observed only after `gh release view` shows a published
  release -- not a local tag, not a draft.
- Record `github-marketplace-index` as observed only after fetching the public
  `marketplace.json` at the documented ref.
- Preserve tag names, commit hashes, URLs, and `gh` output in the `evidence` column.
