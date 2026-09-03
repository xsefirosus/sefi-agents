# Release ledger fixture -- INCOMPLETE: the on-disk surfaces agree, but the three
# GitHub/git surfaces were never checked. Must exit 0 with WARN lines (3/6 observed).

| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|-----------------------------------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | plugin.json:3 "version": "0.6.0" | a README count that happens to agree | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | marketplace.json:4 metadata.version "0.6.0" | updating one occurrence only | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | marketplace.json:10 plugins[0].version "0.6.0" | updating one occurrence only | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | CHANGELOG.md:6 "## [0.6.0] - 2026-09-01" | a ### Added bullet with no dated heading | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | git not checked this session | a local tag never pushed | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | gh not checked this session | a draft release | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | gh not checked this session | install commands in a README only | 2026-09-01T00:00:00Z |
