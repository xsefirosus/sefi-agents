#!/usr/bin/env bash
# Regression coverage for roster bare-slug wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
VALIDATOR="$CORE/scripts/ci/validate-no-orphans.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-no-orphans.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fixture="$TMP/fixture"
mkdir -p "$fixture/plugins"
cp -R "$CORE" "$fixture/plugins/sefi-core"

if bash "$fixture/plugins/sefi-core/scripts/ci/validate-no-orphans.sh" >/dev/null; then
  printf 'PASS: bare agent slugs satisfy roster wiring\n'
else
  printf 'FAIL: bare agent slugs satisfy roster wiring\n' >&2
  exit 1
fi

roster="$fixture/plugins/sefi-core/skills/sefi-orchestration/references/roster.md"
sed -i 's/`systems-auditor`/`systems-auditor-malformed`/' "$roster"
if bash "$fixture/plugins/sefi-core/scripts/ci/validate-no-orphans.sh" >/dev/null 2>&1; then
  printf 'FAIL: malformed agent row is rejected\n' >&2
  exit 1
fi

printf 'test-no-orphans: PASS\n'
