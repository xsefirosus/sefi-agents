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
