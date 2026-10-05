#!/usr/bin/env bash
# Offline contract tests for v0.9.1 documentation Claims and finalization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUNTIME="$ROOT/plugins/sefi-core/scripts/docs-grounding.py"
# MSYS-safe interpreters/paths; see scripts/sefi-python.sh and
# scripts/sefi-native-path.sh.
. "$ROOT/plugins/sefi-core/scripts/sefi-python.sh"
. "$ROOT/plugins/sefi-core/scripts/sefi-native-path.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Use sefi_python_bin, NOT a bare `command -v python3`. On MSYS that yields
# /usr/bin/python3, which is not a usable native interpreter argument: the heredoc reads
# C:\c\Users\...\docs\guide.md and dies with FileNotFoundError inside a command
# substitution whose failure nobody checks, so the suite printed a traceback and still
# reported PASS. Sourcing sefi-python.sh is not enough if the selection below ignores it.
PYBIN="$(sefi_python_bin)" || { echo 'FAIL: no usable Python 3 interpreter' >&2; exit 1; }
run_python() { "$PYBIN" "$@"; }

mkdir -p "$tmp/docs" "$tmp/state/docs-claims/docs"
cat >"$tmp/docs/guide.md" <<'EOF'
# Guide

The guide documents the safe inspection command.

Run `tool --safe` to inspect the repository.
EOF
doc_hash="$(run_python - "$tmp/docs/guide.md" <<'PY'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
cat >"$tmp/source.txt" <<'EOF'
tool --safe
EOF
evidence_hash="$(run_python - "$tmp/source.txt" <<'PY'
import hashlib, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').replace('\r\n', '\n').replace('\r', '\n')
print(hashlib.sha256(source.split('\n')[0].encode()).hexdigest())
PY
)"
cat >"$tmp/state/docs-claims/docs/guide.md.claims.json" <<EOF
{
  "schema": "sefi-doc-claims/v1",
  "document": "docs/guide.md",
  "next_claim_number": 2,
  "verified_document_hash": "$doc_hash",
  "verified_baseline": "baseline-a",
  "claims": [{
    "id": "docs-guide-c0001",
    "statement": "The guide documents the safe inspection command.",
    "evidence": [{
      "id": "ev-source-command",
      "path": "source.txt",
      "start_line": 1,
      "end_line": 1,
      "sha256": "$evidence_hash",
      "baseline": "baseline-a",
      "origin": "direct-repo",
      "derivation": "observed",
      "confidence": "high"
    }],
    "last_verified_baseline": "baseline-a",
    "verified_at": "2026-09-21T00:00:00Z",
    "task_id": "docs-task"
  }]
}
EOF

# A compact local history fixture: an unchanged page, a changed source fact, and a later
# matching page revision exercise the same evolution shape without a provider or network.
NATIVE_TMP="$(sefi_native_path "$tmp")"
git -C "$NATIVE_TMP" init -q
git -C "$NATIVE_TMP" config user.email fixtures@example.invalid
git -C "$NATIVE_TMP" config user.name fixture
git -C "$NATIVE_TMP" add docs/guide.md source.txt state/docs-claims/docs/guide.md.claims.json
git -C "$NATIVE_TMP" commit -qm initial

run_python "$RUNTIME" validate-claims --root "$tmp" --claims state/docs-claims/docs/guide.md.claims.json
run_python "$RUNTIME" preflight --root "$tmp" --claims state/docs-claims/docs/guide.md.claims.json --document docs/guide.md --baseline baseline-a >"$tmp/preflight.json"
grep -Fq '"status": "current"' "$tmp/preflight.json" || { cat "$tmp/preflight.json" >&2; exit 1; }
test -f "$tmp/.sefi/docs/manual/preflight.json"

# A source edit makes the Claim stale. It cannot be published without an explicit decision.
printf 'tool --safer\n' >"$tmp/source.txt"
git -C "$NATIVE_TMP" add source.txt
git -C "$NATIVE_TMP" commit -qm source-change
run_python "$RUNTIME" preflight --root "$tmp" --claims state/docs-claims/docs/guide.md.claims.json --document docs/guide.md --baseline baseline-b >"$tmp/stale.json"
grep -Fq '"status": "stale"' "$tmp/stale.json"
if run_python "$RUNTIME" finalize --root "$tmp" --claims state/docs-claims/docs/guide.md.claims.json --document docs/guide.md --baseline baseline-b --decisions "$tmp/missing.json"; then
  echo 'FAIL: finalization accepted a stale Claim with no decision' >&2
  exit 1
fi

cat >"$tmp/docs/guide.md" <<'EOF'
# Guide

The guide documents the safer inspection command.

Run `tool --safer` to inspect the repository.
EOF
git -C "$NATIVE_TMP" add docs/guide.md
git -C "$NATIVE_TMP" commit -qm document-update
test "$(git -C "$NATIVE_TMP" rev-list --count HEAD)" -eq 3

cat >"$tmp/decisions.json" <<'EOF'
[{"id":"docs-guide-c0001","decision":"update","statement":"The guide documents the safer inspection command.","evidence":[{"id":"ev-source-command-v2","path":"source.txt","start_line":1,"end_line":1,"origin":"direct-repo","derivation":"observed","confidence":"high"}]}]
EOF
run_python "$RUNTIME" finalize --root "$tmp" --claims state/docs-claims/docs/guide.md.claims.json --document docs/guide.md --baseline baseline-b --decisions "$tmp/decisions.json" --task docs-task-v2 --manifest state/docs-manifest.json
run_python "$RUNTIME" validate-manifest --root "$tmp" --manifest state/docs-manifest.json

# Credentials must never be allowed into a Claim artifact.
cp "$tmp/state/docs-claims/docs/guide.md.claims.json" "$tmp/unsafe.json"
run_python - "$tmp/unsafe.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); data = json.loads(p.read_text())
data['claims'][0]['statement'] = 'token=sk-test-secret'
p.write_text(json.dumps(data), encoding='utf-8')
PY
if run_python "$RUNTIME" validate-claims --root "$tmp" --claims unsafe.json; then
  echo 'FAIL: credential-shaped Claim content was accepted' >&2
  exit 1
fi

echo 'test-documentation-grounding-v091: PASS'
