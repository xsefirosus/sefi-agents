#!/usr/bin/env bash
# Clean-room, offline behavior-contract checks for v0.8.0 agent guidance.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }
has() { grep -RqsF -- "$2" "$1"; }

for item in \
  "inspect-before-act" \
  "plan/execute separation" \
  "meaningful progress" \
  "untrusted content" \
  "uncertainty" \
  "verification-before-completion" \
  "approval boundary"; do
  if has "$CORE" "$item"; then ok "contract exists: $item"; else bad "contract missing: $item"; fi
done

if has "$CORE" "never copy vendor prompts"; then
  ok 'clean-room prompt rule exists'
else
  bad 'clean-room prompt rule is missing'
fi

if [ "$fail" -ne 0 ]; then
  printf 'test-v08-conformance: %s failed, %s passed\n' "$fail" "$pass"
  exit 1
fi
printf 'test-v08-conformance: OK (%s passed)\n' "$pass"
