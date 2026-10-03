#!/usr/bin/env bash
# CI: prune-stale-skill-entries.sh -- only dangling entries are removed.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$CORE/scripts/prune-stale-skill-entries.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-prune.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  PASS: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

make_fixture() {
  # lock.json records three skills; only two exist on disk.
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/.hub" "$root/live-a" "$root/live-b"
  cat > "$root/.hub/lock.json" <<'JSON'
{
  "version": 1,
  "installed": {
    "live-a": {"install_path": "live-a", "identifier": "skills-sh/x/y/live-a"},
    "live-b": {"install_path": "live-b", "identifier": "skills-sh/x/y/live-b"},
    "ghost":  {"install_path": "ghost",  "identifier": "skills-sh/x/y/ghost"}
  }
}
JSON
}

echo "=== prune-stale-skill-entries.sh (registry self-heal) ==="

make_fixture "$TMP/root"

# 1. Dry run reports the dangling entry and changes nothing.
out="$(bash "$SCRIPT" --skills-root "$TMP/root" 2>&1)"
if [ "$(grep -c ghost <<<"$out")" -ge 1 ]; then
  ok "dry run names the dangling entry"
else
  bad "dry run did not name the dangling entry: $out"
fi
if grep -q ghost "$TMP/root/.hub/lock.json"; then
  ok "dry run left the registry untouched"
else
  bad "dry run modified the registry"
fi

# 2. Apply removes exactly the dangling entry and keeps both live ones.
out="$(bash "$SCRIPT" --skills-root "$TMP/root" --apply 2>&1)"
if grep -q ghost "$TMP/root/.hub/lock.json"; then
  bad "apply did not remove the dangling entry"
else
  ok "apply removed the dangling entry"
fi
for name in live-a live-b; do
  if grep -q "\"$name\"" "$TMP/root/.hub/lock.json" && [ -d "$TMP/root/$name" ]; then
    ok "live skill preserved: $name"
  else
    bad "live skill damaged: $name"
  fi
done
if [ "$(grep -c '"install_path"' "$TMP/root/.hub/lock.json")" -eq 2 ]; then
  ok "exactly two entries remain"
else
  bad "entry count wrong: $(grep -c '"install_path"' "$TMP/root/.hub/lock.json")"
fi

# 3. A backup of the pre-change registry exists.
if compgen -G "$TMP/root/.hub/lock.json.bak-*" >/dev/null 2>&1; then
  ok "pre-change registry backed up"
else
  bad "no backup written"
fi

# 4. Idempotent: a second apply reports consistency and changes nothing.
out="$(bash "$SCRIPT" --skills-root "$TMP/root" --apply 2>&1)"
if grep -qi "nothing to prune" <<<"$out"; then
  ok "second apply is a no-op (idempotent)"
else
  bad "second apply was not a no-op: $out"
fi

# 5. A consistent registry is left completely alone.
make_fixture "$TMP/root2"
python3 -c '
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
del d["installed"]["ghost"]
p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
' "$TMP/root2/.hub/lock.json" 2>/dev/null || python -c '
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
del d["installed"]["ghost"]
p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
' "$TMP/root2/.hub/lock.json"
before="$(cat "$TMP/root2/.hub/lock.json")"
bash "$SCRIPT" --skills-root "$TMP/root2" --apply >/dev/null 2>&1
after="$(cat "$TMP/root2/.hub/lock.json")"
if [ "$before" = "$after" ]; then
  ok "consistent registry left byte-identical"
else
  bad "consistent registry was modified"
fi

# 6. A missing registry is refused, not created.
if bash "$SCRIPT" --skills-root "$TMP/absent" --apply >/dev/null 2>&1; then
  bad "missing registry was not refused"
else
  ok "missing registry refused"
fi

# 7. Unknown argument is a usage error.
if bash "$SCRIPT" --bogus >/dev/null 2>&1; then
  bad "unknown arg accepted"
else
  ok "unknown arg exits nonzero"
fi

echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ]
