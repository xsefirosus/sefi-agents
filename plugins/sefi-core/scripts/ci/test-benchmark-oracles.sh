#!/usr/bin/env bash
# Offline regressions for the frozen benchmark acceptance oracles.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/benchmarks"
cp -R "$ROOT/benchmarks/sandbox" "$tmp/benchmarks/sandbox"

must_reject() {
  local label="$1" check="$2"
  if sh "$check" "$tmp" >/dev/null 2>&1; then
    echo "FAIL: $label was accepted" >&2
    exit 1
  fi
}

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' > "$tmp/benchmarks/sandbox/deploy.sh"
must_reject "a shell script whose original body was deleted" "$ROOT/benchmarks/cases/check_sh-strict-mode.sh"

printf '%s\n' '{' '  "unrelated": false' '}' > "$tmp/benchmarks/sandbox/config.json"
must_reject "valid-looking JSON with changed content" "$ROOT/benchmarks/cases/check_json-trailing-newline.sh"

printf '%s\n' '# Release notes' > "$tmp/benchmarks/sandbox/NOTES.md"
must_reject "release notes whose body was deleted" "$ROOT/benchmarks/cases/check_notes-single-h1.sh"

cp "$ROOT/benchmarks/sandbox/deploy.sh" "$tmp/benchmarks/sandbox/deploy.sh"
sed '3i set -euo pipefail' "$tmp/benchmarks/sandbox/deploy.sh" > "$tmp/deploy.sh"
mv "$tmp/deploy.sh" "$tmp/benchmarks/sandbox/deploy.sh"
sh "$ROOT/benchmarks/cases/check_sh-strict-mode.sh" "$tmp" >/dev/null

cat > "$tmp/benchmarks/sandbox/config.json" <<'JSON'
{
  "name": "sample",
  "version": "1.0.0",
  "features": {
    "a": true,
    "b": false
  },
  "tags": [
    "x",
    "y"
  ]
}
JSON
sh "$ROOT/benchmarks/cases/check_json-trailing-newline.sh" "$tmp" >/dev/null

sed 's/^# Details$/## Details/' "$ROOT/benchmarks/sandbox/NOTES.md" > "$tmp/benchmarks/sandbox/NOTES.md"
sh "$ROOT/benchmarks/cases/check_notes-single-h1.sh" "$tmp" >/dev/null

for case_id in sh-strict-mode json-trailing-newline notes-single-h1; do
  actual="$(cat "$ROOT/benchmarks/prompts/$case_id.md" "$ROOT/benchmarks/cases/check_$case_id.sh" | sha256sum | cut -c1-64)"
  recorded="$(sed -n "/\"case_id\": \"$case_id\"/,/}/s/.*\"case_fingerprint\": \"\([0-9a-f]*\)\".*/\1/p" "$ROOT/benchmarks/cases.json" | head -1)"
  [ "$actual" = "$recorded" ] || { echo "FAIL: stale fingerprint for $case_id" >&2; exit 1; }
done
