# Release ledger fixture -- CONTRADICTION: two observed surfaces disagree for the latest
# version claim (git tag pushed ahead of the plugin.json bump). Must HARD-FAIL exit 1.

| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|-----------------------------------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | plugin.json:3 "version": "0.6.0" | a README count that happens to agree | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | marketplace.json:4 metadata.version "0.6.0" | updating one occurrence only | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | CHANGELOG.md:6 "## [0.6.0] - 2026-09-01" | a ### Added bullet with no dated heading | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | 0.6.1 | mismatch | git tag --points-at HEAD -> v0.6.1 | a local tag never pushed | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | gh release view v0.6.0 -> exit 1 | a draft release | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | not checked | install commands in a README only | 2026-09-01T00:00:00Z |
