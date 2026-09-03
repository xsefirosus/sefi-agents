# Release ledger fixture -- OK: every surface observed and consistent for the latest version.

| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|-----------------------------------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | plugin.json:3 "version": "0.6.0" | a README count that happens to agree | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | marketplace.json:4 metadata.version "0.6.0" | updating one occurrence only | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | marketplace.json:10 plugins[0].version "0.6.0" | updating one occurrence only | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | CHANGELOG.md:6 "## [0.6.0] - 2026-09-01" | a ### Added bullet with no dated heading | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | 0.6.0 | match | git tag --points-at HEAD -> v0.6.0 ; git ls-remote --tags origin -> v0.6.0 | a local tag never pushed | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | 0.6.0 | match | gh release view v0.6.0 -> published 2026-09-01 | a draft release | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | 0.6.0 | match | gh api .../marketplace.json (raw) -> metadata.version 0.6.0, plugins[0].version 0.6.0 | install commands in a README only | 2026-09-01T00:00:00Z |
