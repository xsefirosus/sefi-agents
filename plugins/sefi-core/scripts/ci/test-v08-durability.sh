#!/usr/bin/env bash
# Offline contracts for v0.8.0 task receipts, continuations, and source manifests.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
S="$ROOT/plugins/sefi-core/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }

if git -C "$ROOT" check-ignore -q memory/sessions/example.md; then
  ok 'runtime memory paths are ignored at repository root'
else
  bad 'runtime memory paths are not ignored at repository root'
fi
if git -C "$ROOT" ls-files --error-unmatch memory/index.md >/dev/null 2>&1; then
  bad 'repository root still tracks runtime memory'
else
  ok 'repository root does not track runtime memory'
fi

mkdir -p "$TMP/project"
printf 'input payload\n' > "$TMP/project/input.txt"
printf 'output payload\n' > "$TMP/project/output.txt"

if bash "$S/record-run-receipt.sh" --root "$TMP/project" --session session-1 --task map-code --agent codebase-cartographer --tier low --state completed --input "$TMP/project/input.txt" --output "$TMP/project/output.txt" --route match --retry 0; then
  receipt="$TMP/project/.sefi/runs/session-1/receipt-map-code.json"
  [ -f "$receipt" ] && ok 'completed receipt is written under the session run directory' || bad 'completed receipt path is missing'
  grep -q 'input payload' "$receipt" && bad 'receipt leaks input content' || ok 'receipt stores hashes instead of input content'
  grep -q '"state": "completed"' "$receipt" && ok 'receipt records lifecycle state' || bad 'receipt lacks lifecycle state'
else
  bad 'valid receipt command is rejected'
fi

if bash "$S/record-run-receipt.sh" --root "$TMP/project" --session session-1 --task bad-state --agent codebase-cartographer --tier low --state invented --input "$TMP/project/input.txt" --output "$TMP/project/output.txt" --route match --retry 0 >/dev/null 2>&1; then
  bad 'unknown lifecycle state is accepted'
else
  ok 'unknown lifecycle state is rejected'
fi

if bash "$S/record-continuation.sh" --root "$TMP/project" --session session-1 --goal 'release v0.8.0' --plan-step 12 --reason 'offline validation remains' --state needs-attention; then
  continuation="$TMP/project/.sefi/runs/session-1/continuation.json"
  [ -f "$continuation" ] && ok 'explicit goal continuation is recorded' || bad 'explicit goal continuation is missing'
else
  bad 'valid continuation is rejected'
fi

if bash "$S/record-continuation.sh" --root "$TMP/project" --session session-1 --goal '' --plan-step '' --reason 'ordinary chat' --state running >/dev/null 2>&1; then
  bad 'continuation without an explicit goal or plan step is accepted'
else
  ok 'continuation without explicit work is rejected'
fi

cp -R "$ROOT/plugins/sefi-core" "$TMP/project/package"
if bash "$S/package-manifest.sh" create --root "$TMP/project" --source "$ROOT/plugins/sefi-core" --destination "$TMP/project/package"; then
  manifest="$TMP/project/package/.sefi-agents-manifest.json"
  [ -f "$manifest" ] && ok 'package source manifest is created' || bad 'package source manifest is missing'
  bash "$S/package-manifest.sh" check --root "$TMP/project" --destination "$TMP/project/package" >/dev/null 2>&1 && ok 'unchanged package manifest verifies' || bad 'unchanged package manifest does not verify'
  printf 'drift\n' >> "$TMP/project/package/README.md"
  if bash "$S/package-manifest.sh" check --root "$TMP/project" --destination "$TMP/project/package" >/dev/null 2>&1; then
    bad 'changed managed package file is accepted'
  else
    ok 'changed managed package file is detected'
  fi
else
  bad 'package manifest creation is rejected'
fi

if [ "$fail" -ne 0 ]; then
  printf 'test-v08-durability: %s failed, %s passed\n' "$fail" "$pass"
  exit 1
fi
printf 'test-v08-durability: OK (%s passed)\n' "$pass"
