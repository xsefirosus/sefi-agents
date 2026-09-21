#!/usr/bin/env bash
# Local behavior checks for the v0.9.1 Cartographer runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUNTIME="$ROOT/plugins/sefi-core/scripts/cartographer-runtime.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then PYTHON=(python3)
elif command -v py >/dev/null 2>&1; then PYTHON=(py -3)
else echo 'FAIL: Python 3 is required' >&2; exit 1; fi
run_python() { "${PYTHON[@]}" "$@"; }

mkdir -p "$tmp/src" "$tmp/docs"
cat >"$tmp/src/app.py" <<'EOF'
from helpers import answer

def run():
    return answer()
EOF
cat >"$tmp/src/helpers.py" <<'EOF'
def answer():
    return 42
EOF
cat >"$tmp/docs/outside.md" <<'EOF'
# Outside the requested context
EOF
git -C "$tmp" init -q
git -C "$tmp" config user.email fixtures@example.invalid
git -C "$tmp" config user.name fixture
git -C "$tmp" add src
git -C "$tmp" commit -qm initial

run_python "$RUNTIME" map --root "$tmp" --slug sample --target src
run_python "$RUNTIME" validate --root "$tmp" --map state/codebase-map-sample.json
grep -Fq 'sefi-codebase-map/v2' "$tmp/state/codebase-map-sample.json"
grep -Fq '"classification": "unchanged"' "$tmp/state/codebase-map-sample.json"

# Comments change bytes but not the normalized topology.
printf '# explanatory comment\n' | cat - "$tmp/src/helpers.py" >"$tmp/helpers.next"
mv "$tmp/helpers.next" "$tmp/src/helpers.py"
run_python "$RUNTIME" map --root "$tmp" --slug sample --target src
grep -Fq '"classification": "content-only"' "$tmp/state/codebase-map-sample.json"

# A changed selected source line makes existing evidence stale until the map is refreshed.
sed -i 's/return 42/return 43/' "$tmp/src/helpers.py"
if run_python "$RUNTIME" validate --root "$tmp" --map state/codebase-map-sample.json; then
  echo 'FAIL: stale source evidence was accepted as current' >&2
  exit 1
fi
run_python "$RUNTIME" map --root "$tmp" --slug sample --target src

# A signature change is topology, not a content-only edit.
sed -i 's/def run():/def run(extra=None):/' "$tmp/src/app.py"
run_python "$RUNTIME" map --root "$tmp" --slug sample --target src
grep -Fq '"classification": "structural"' "$tmp/state/codebase-map-sample.json"

# Map the repository, then ensure CONTEXT honors its narrower requested target.
run_python "$RUNTIME" map --root "$tmp" --slug sample --target .
run_python "$RUNTIME" context --root "$tmp" --slug sample --target src --budget 4000
test -f "$tmp/.sefi/cartographer/sample/packet-001.md"
test -f "$tmp/.sefi/cartographer/sample/manifest.json"
if grep -Fq 'docs/outside.md' "$tmp/.sefi/cartographer/sample/packet-001.md"; then
  echo 'FAIL: context packet included files outside its requested target' >&2
  exit 1
fi
run_python "$RUNTIME" visualize --root "$tmp" --slug sample
grep -Fq "Content-Security-Policy" "$tmp/.sefi/cartographer/sample/viewer.html"
grep -Fq "script-src 'unsafe-inline'" "$tmp/.sefi/cartographer/sample/viewer.html"
if run_python "$RUNTIME" context --root "$tmp" --slug sample --target 'C:/private/project' --budget 4000; then
  echo 'FAIL: context accepted an absolute private path' >&2
  exit 1
fi

# Unsafe source paths and unsupported edges cannot enter a published map.
cp "$tmp/state/codebase-map-sample.json" "$tmp/unsafe-map.json"
run_python - "$tmp/unsafe-map.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); data = json.loads(p.read_text())
data['files'][0]['path'] = '../escape.py'
p.write_text(json.dumps(data), encoding='utf-8')
PY
if run_python "$RUNTIME" validate --root "$tmp" --map unsafe-map.json; then
  echo 'FAIL: unsafe path was accepted' >&2
  exit 1
fi

echo 'test-cartographer-runtime-v091: PASS'
