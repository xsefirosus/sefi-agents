# Release ledger -- machine bookkeeping. One row per observed publication surface, appended by the release-tracking skill. Never hand-edited except to append; never rewrite history to hide a lag.
<!-- surface = one of: plugin.json | marketplace.json | changelog | git-tag | github-release | github-marketplace-index. status = match | lag | mismatch | unobserved. Target version is resolved from plugins/sefi-core/.claude-plugin/plugin.json, never from prose. -->

| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|-----------------------------------|--------------------|------------|
| 0.5.2 | plugin.json | 0.5.2 | 0.5.2 | match | plugins/sefi-core/.claude-plugin/plugin.json:3 "version": "0.5.2" | a README count or CHANGELOG heading that happens to agree | 2026-08-30T18:58:58Z |
| 0.5.2 | marketplace.json | 0.5.2 | 0.5.2 | match | .claude-plugin/marketplace.json:4 metadata.version "0.5.2" | updating one occurrence and assuming the other followed | 2026-08-30T18:58:58Z |
| 0.5.2 | marketplace.json | 0.5.2 | 0.5.2 | match | .claude-plugin/marketplace.json:10 plugins[0].version "0.5.2" | updating one occurrence and assuming the other followed | 2026-08-30T18:58:58Z |
| 0.5.2 | changelog | 0.5.2 | 0.5.2 | match | CHANGELOG.md first versioned heading "## [0.5.2] - 2026-08-29" (above it: "## [Unreleased] - 2026-08-30") | a ### Added bullet with no dated heading above it | 2026-08-30T18:58:58Z |
| 0.5.2 | git-tag | 0.5.2 | 0.5.2 | match | git tag -l -> v0.5.2 ; git ls-remote --tags origin -> b389809 refs/tags/v0.5.2 . NOTE: v0.5.2 points at 3bd9f5e, and HEAD 6bf47a3 is 1 commit of unreleased work past it (git rev-list --count v0.5.2..HEAD -> 1) -- normal inter-release state, not a lag of the 0.5.2 release, which is fully tagged local and origin | a local tag that was never pushed to origin | 2026-08-30T18:58:58Z |
| 0.5.2 | github-release | 0.5.2 | unobserved | unobserved | gh release list -> empty ; gh release view v0.5.2 -> exit 1 "release not found" | a local or pushed tag with no release; a draft release | 2026-08-30T18:58:58Z |
| 0.5.2 | github-marketplace-index | 0.5.2 | 0.5.2 | match | gh api repos/xsefirosus/sefi-agents/contents/.claude-plugin/marketplace.json (Accept: raw) -> metadata.version 0.5.2, plugins[0].version 0.5.2 | install commands quoted only in a README | 2026-08-30T18:58:58Z |
| 0.5.1 | git-tag | 0.5.1 | 0.5.1 | match | git ls-remote --tags origin -> c7545ba refs/tags/v0.5.1 | a local tag that was never pushed to origin | 2026-08-30T18:58:58Z |
| 0.5.1 | changelog | 0.5.1 | 0.5.1 | match | CHANGELOG.md:38 "## [0.5.1] - 2026-08-28" (historical entry retained) | a ### Added bullet with no dated heading above it | 2026-08-30T18:58:58Z |
| 0.5.1 | github-release | 0.5.1 | unobserved | unobserved | gh release view v0.5.1 -> exit 1 "release not found" | a local or pushed tag with no release; a draft release | 2026-08-30T18:58:58Z |
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | plugins/sefi-core/.claude-plugin/plugin.json version key "0.6.0" (bumped in this release commit) | a README count or CHANGELOG heading that happens to agree | 2026-09-03T08:31:30Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | .claude-plugin/marketplace.json metadata.version "0.6.0" | updating one occurrence and assuming the other followed | 2026-09-03T08:31:30Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | .claude-plugin/marketplace.json plugins[0].version "0.6.0" | updating one occurrence and assuming the other followed | 2026-09-03T08:31:30Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | CHANGELOG.md first versioned heading "## [0.6.0] - 2026-09-03" (above it: "## [Unreleased]") | a ### Added bullet with no dated heading above it | 2026-09-03T08:31:30Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | PENDING -- orchestrator tags v0.6.0 after this commit; git tag -l shows no v0.6.0 at commit time | a local tag that was never pushed to origin | 2026-09-03T08:31:30Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | PENDING -- orchestrator creates the GitHub release after tagging; gh release view v0.6.0 -> release not found | a local or pushed tag with no release; a draft release | 2026-09-03T08:31:30Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | PENDING -- release commit not pushed at commit time; gh api raw marketplace.json on origin still reads 0.5.2 | install commands quoted only in a README | 2026-09-03T08:31:30Z |
| 0.6.0 | git-tag | 0.6.0 | 0.6.0 | match | git tag -l v0.6.0 -> v0.6.0 ; git ls-remote --tags origin v0.6.0 -> 192a96ad2e3eacbe3e8d3f5a8c36a586482f3a64 refs/tags/v0.6.0 ; git rev-parse v0.6.0^{commit} -> 9d5813e7d1bf93d2c6dfc842ad9719d893d7aec9 (ancestor of origin/main @ fab099b, pushed) | a local tag that was never pushed to origin | 2026-09-03T17:06:31Z |
| 0.6.0 | github-release | 0.6.0 | 0.6.0 | match | gh release view v0.6.0 --json tagName,isDraft,url,publishedAt -> tagName=v0.6.0, url=https://github.com/xsefirosus/sefi-agents/releases/tag/v0.6.0, publishedAt=2026-09-03T17:03:41Z, isDraft=false | a local or pushed tag with no release; a draft release | 2026-09-03T17:06:31Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | 0.6.0 | match | gh api repos/xsefirosus/sefi-agents/contents/.claude-plugin/marketplace.json?ref=main (Accept: raw) -> metadata.version 0.6.0, plugins[0].version 0.6.0 | install commands quoted only in a README | 2026-09-03T17:06:31Z |

## Notes

- 2026-08-30: backfill of the current tree at commit 6bf47a3. All five in-repo / tag
  surfaces agree on 0.5.2: `plugin.json`, `marketplace.json` (both occurrences), the
  `CHANGELOG.md` top versioned heading, and the `v0.5.2` git tag (local and `origin`).
  The GitHub marketplace index (`gh api` raw `marketplace.json`) also reads 0.5.2.
- git-tag status is `match`, not `lag`: the skill's surface contract asks that `v<target>`
  exist locally and on `origin`, which `v0.5.2` does. It points at 3bd9f5e while HEAD is 1
  commit further on; that gap is ordinary unreleased work between releases, not the 0.5.2
  release trailing a surface. If a later bump makes `plugin.json` move ahead of the newest
  tag, that future row is a `lag`.
- `github-release` is `unobserved` for both 0.5.1 and 0.5.2: `gh` was available,
  `gh release list` is empty, and `gh release view` exits 1 for each tag. Per the evidence
  rule, no confirmed release is recorded as `unobserved`, not as a definitive negative.
- Superseded observation (2026-08-30, earlier same day): an orphaned `v0.5.3` tag briefly
  existed on HEAD (local and `origin`) while every version surface read 0.5.2;
  `validate-release-ledger.sh` hard-failed on that contradiction as designed. The release
  owner deleted the premature `v0.5.3` tag from local and `origin`; this backfill reflects
  the corrected state. The earlier hard-fail is retained here as history, not erased.
- 2026-08-31: evidence-locator correction (append-only; the row above is left byte-for-byte
  intact). The `0.5.1` / `changelog` row cites `CHANGELOG.md:38` for the
  `## [0.5.1] - 2026-08-28` heading. `CHANGELOG.md:38` does not locate that heading. Cite
  the heading text `## [0.5.1] - 2026-08-28` rather than any line number -- the heading's
  line keeps moving as content is added to the `[Unreleased]` block above it. The row's
  `observed` value (`0.5.1`) is still reproducible from that heading; only its locator
  moved. This note supersedes the `:38` locator.
- 2026-08-31: re-scan of every other citation in this file for the same line-drift, done at
  build time, using non-drifting key-path locators instead of line numbers.
  `plugin.json` `version` key -> `0.5.2`, verified. `marketplace.json` `metadata.version`
  -> `0.5.2`, verified. `marketplace.json` `plugins[0].version` -> `0.5.2`, verified. Read
  the row-level evidence in the table above by the same key-path form (the JSON key name,
  which each of those rows already states); the `:3` / `:4` / `:10` prefixes in those
  cells are the same drift-prone locators and are superseded by the key paths named beside
  them. The `0.5.2` / `changelog` row and the `0.5.2` / `github-marketplace-index` row
  cite command output or heading text with no brittle line number. Only the `0.5.1` /
  `changelog` row had drifted; it is corrected in the note above.
- 2026-09-03: 0.6.0 release-prep rows appended (append-only; every 0.5.x row left
  byte-for-byte intact). Three in-repo surfaces observed 0.6.0 in the release commit --
  `plugin.json` `version`, `marketplace.json` (both `metadata.version` and
  `plugins[0].version`), and the `CHANGELOG.md` top versioned heading
  `## [0.6.0] - 2026-09-03`. `git-tag`, `github-release`, and `github-marketplace-index`
  are `unobserved` (not `mismatch`): at commit time the release worktree branch
  `release/0.6.0` is not tagged, not released, and not pushed -- the orchestrator
  fast-forwards `main`, tags `v0.6.0`, pushes, and cuts the GitHub release as the next
  step, after which those three rows get their own observed append.
  `validate-release-ledger.sh` exits 0 with
  `OK (latest 0.6.0, 3/6 surfaces observed, 3 warning(s))`; the three warnings are the
  three PENDING surfaces above.
- 2026-09-03: 0.6.0 tag + release + marketplace-index reconciled (append-only; the three
  PENDING `unobserved` rows above are left byte-for-byte intact as the at-commit-time
  record and are superseded, not edited, by the observed appends below them). `v0.6.0` is
  now tagged local AND on `origin`: `git tag -l v0.6.0` -> `v0.6.0`;
  `git ls-remote --tags origin v0.6.0` -> `192a96ad2e3eacbe3e8d3f5a8c36a586482f3a64
  refs/tags/v0.6.0`; `git rev-parse v0.6.0^{commit}` -> `9d5813e7d1bf93d2c6dfc842ad9719d893d7aec9`,
  an ancestor of `origin/main`. `main` was pushed and is at `fab099b` on `origin`. The
  GitHub release is live and published (not a draft): `gh release view v0.6.0` ->
  tagName `v0.6.0`, url https://github.com/xsefirosus/sefi-agents/releases/tag/v0.6.0,
  publishedAt `2026-09-03T17:03:41Z`, isDraft=false. `github-marketplace-index` also
  caught up -- `gh api .../contents/.claude-plugin/marketplace.json?ref=main` (raw) now
  serves `metadata.version` 0.6.0 and `plugins[0].version` 0.6.0 -- so it gets a `match`
  append here too. All six 0.6.0 surfaces are now observed.
  `validate-release-ledger.sh` exits 0 with
  `OK (latest 0.6.0, 6/6 surfaces observed, 0 warning(s))`.
