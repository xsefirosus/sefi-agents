#!/usr/bin/env bash
# prune-stale-skill-entries.sh -- drop registry entries whose skill directory is gone.
#
# WHY THIS EXISTS (live-confirmed on Windows/MSYS, 2026-10-03)
# Hermes records every installed skill in skills/.hub/lock.json. When
# install-hermes.sh rolls back a failed run it removes the skill DIRECTORIES but
# cannot un-register them. The next run then sees "already installed" for skills
# that no longer exist on disk, skips them, and the installer reports them
# missing. That wedged three consecutive install attempts identically: no retry
# could ever succeed because each retry re-poisoned the registry on rollback.
#
# This removes an entry ONLY when its recorded install_path does not exist on
# disk. A live skill is never touched. A timestamped backup is written first, so
# the registry can be restored by hand.
#
# Usage: bash prune-stale-skill-entries.sh [--skills-root <dir>] [--apply]
#        Without --apply it reports what it would remove and exits 0.
set -euo pipefail

SKILLS_ROOT=""
APPLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skills-root) SKILLS_ROOT="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help)
      echo "usage: $0 [--skills-root <dir>] [--apply]"
      exit 0 ;;
    *) echo "prune-stale-skill-entries.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

find_python() {
  # MSYS-safe launcher; see sefi-python.sh for why the wrapper is required.
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sefi-python.sh"
  sefi_python_bin
}

PYBIN="$(find_python)" || {
  echo "prune-stale-skill-entries.sh: Python 3.11+ is required" >&2
  exit 2
}

if [ -z "$SKILLS_ROOT" ]; then
  CONFIG_PATH="$(hermes config path 2>/dev/null)" || {
    echo "prune-stale-skill-entries.sh: cannot locate Hermes config path" >&2
    exit 1
  }
  SKILLS_ROOT="$(dirname "$CONFIG_PATH")/skills"
fi

LOCK="$SKILLS_ROOT/.hub/lock.json"
[ -f "$LOCK" ] || {
  echo "prune-stale-skill-entries.sh: no skill registry at $LOCK" >&2
  exit 1
}
[ -d "$SKILLS_ROOT" ] && [ ! -L "$SKILLS_ROOT" ] || {
  echo "prune-stale-skill-entries.sh: refusing non-directory skills root $SKILLS_ROOT" >&2
  exit 1
}

if [ "$APPLY" -eq 1 ]; then
  "$PYBIN" - "$LOCK" "$SKILLS_ROOT" <<'PYEOF'
import json
import shutil
import sys
import time
from pathlib import Path

lock = Path(sys.argv[1])
root = Path(sys.argv[2])
data = json.loads(lock.read_text(encoding="utf-8"))
installed = data.get("installed")
if not isinstance(installed, dict):
    raise SystemExit("skill registry has no installed dict")

stale = sorted(
    name for name, entry in installed.items()
    if not (root / str(entry.get("install_path", name))).is_dir()
)
if not stale:
    print("prune-stale-skill-entries.sh: registry consistent; nothing to prune")
    raise SystemExit(0)

backup = lock.with_suffix(f".json.bak-{time.strftime('%Y%m%d-%H%M%S')}")
shutil.copy2(lock, backup)
for name in stale:
    del installed[name]
lock.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8", newline="\n")
print(f"prune-stale-skill-entries.sh: backup {backup}")
print(f"prune-stale-skill-entries.sh: pruned {len(stale)} stale entries: {' '.join(stale)}")
print(f"prune-stale-skill-entries.sh: {len(installed)} entries remain, all present on disk")
PYEOF
else
  "$PYBIN" - "$LOCK" "$SKILLS_ROOT" <<'PYEOF'
import json
import sys
from pathlib import Path

lock = Path(sys.argv[1])
root = Path(sys.argv[2])
installed = json.loads(lock.read_text(encoding="utf-8")).get("installed", {})
stale = sorted(
    name for name, entry in installed.items()
    if not (root / str(entry.get("install_path", name))).is_dir()
)
if stale:
    print(f"prune-stale-skill-entries.sh: {len(stale)} stale entries would be pruned: {' '.join(stale)}")
else:
    print("prune-stale-skill-entries.sh: registry consistent; nothing to prune")
PYEOF
fi
