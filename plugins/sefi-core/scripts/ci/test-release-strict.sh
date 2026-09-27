#!/usr/bin/env bash
# Release preparation may warn about unobserved surfaces; release completion may not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$ROOT/plugins/sefi-core/scripts/ci/validate-release-ledger.sh"
FIXTURE="$ROOT/plugins/sefi-core/scripts/ci/fixtures/release-ledger/incomplete/ledger.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! bash "$SCRIPT" --ledger "$FIXTURE" --root "$tmp" >/dev/null; then
  echo "FAIL: preparation validation should retain warning-only behavior" >&2
  exit 1
fi
if bash "$SCRIPT" --strict --ledger "$FIXTURE" --root "$tmp" >/dev/null 2>&1; then
  echo "FAIL: strict release completion must reject unobserved surfaces" >&2
  exit 1
fi

# A prepared release may truthfully record a public surface that still serves the prior
# version. That is lag, not missing evidence: preparation passes, strict completion does
# not. The empty root keeps this focused on the ledger contract.
lag_ledger="$tmp/lag.md"
cat >"$lag_ledger" <<'EOF'
| version | surface | expected | observed | status | evidence (cmd output or file:line) | common-false-proof | observed-at |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0.9.4 | plugin.json | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:00:00Z |
| 0.9.4 | marketplace.json | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:00:00Z |
| 0.9.4 | changelog | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:00:00Z |
| 0.9.4 | git-tag | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:00:00Z |
| 0.9.4 | github-release | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:00:00Z |
| 0.9.4 | github-marketplace-index | 0.9.4 | 0.9.3 | lag | fixture | none | 2026-09-26T00:00:00Z |
EOF

if ! bash "$SCRIPT" --ledger "$lag_ledger" --root "$tmp" >/dev/null; then
  echo "FAIL: a prior-version lag must pass preparation validation" >&2
  exit 1
fi
if bash "$SCRIPT" --strict --ledger "$lag_ledger" --root "$tmp" >/dev/null 2>&1; then
  echo "FAIL: strict release completion must reject an observed lag surface" >&2
  exit 1
fi

equal_lag_ledger="$tmp/equal-lag.md"
sed 's/0.9.3 | lag/0.9.4 | lag/' "$lag_ledger" >"$equal_lag_ledger"
if bash "$SCRIPT" --ledger "$equal_lag_ledger" --root "$tmp" >/dev/null 2>&1; then
  echo "FAIL: a lag surface equal to its expected version must fail" >&2
  exit 1
fi

ahead_lag_ledger="$tmp/ahead-lag.md"
sed 's/0.9.3 | lag/0.9.5 | lag/' "$lag_ledger" >"$ahead_lag_ledger"
if bash "$SCRIPT" --ledger "$ahead_lag_ledger" --root "$tmp" >/dev/null 2>&1; then
  echo "FAIL: a lag surface ahead of its expected version must fail" >&2
  exit 1
fi

ahead_mismatch_ledger="$tmp/ahead-mismatch.md"
sed 's/0.9.3 | lag/0.9.5 | mismatch/' "$lag_ledger" >"$ahead_mismatch_ledger"
if bash "$SCRIPT" --ledger "$ahead_mismatch_ledger" --root "$tmp" >/dev/null 2>&1; then
  echo "FAIL: an ahead mismatch must remain a preparation failure" >&2
  exit 1
fi

# The ledger is append-only. A later observation for the same latest-version surface
# supersedes an earlier lag, so strict completion evaluates only the latest row.
superseded_lag_ledger="$tmp/superseded-lag.md"
cp "$lag_ledger" "$superseded_lag_ledger"
cat >>"$superseded_lag_ledger" <<'EOF'
| 0.9.4 | github-marketplace-index | 0.9.4 | 0.9.4 | match | fixture | none | 2026-09-26T00:01:00Z |
EOF
if ! bash "$SCRIPT" --strict --ledger "$superseded_lag_ledger" --root "$tmp" >/dev/null; then
  echo "FAIL: a latest match must supersede an earlier lag for the same surface" >&2
  exit 1
fi
