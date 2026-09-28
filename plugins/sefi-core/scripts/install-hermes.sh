#!/usr/bin/env bash
# install-hermes.sh -- install every sefi-core skill into Hermes via its native
# `hermes skills install` command. Hermes has no bulk-install verb, so this loops
# one call per skill. It also maintains a canonical runtime beside Hermes's config:
# native skills need that runtime for agents, commands, scripts, and references.
#
# Two skills (sefi-orchestration, security-review) are attempted with --force.
# Hermes's community-skill scanner can flag their *content* as DANGEROUS on
# substring match: sefi-orchestration's references name shell/hooks/subagent
# dispatch; security-review's checklist names dangerous patterns (eval/exec,
# curl-to-shell, unpinned installs) precisely in order to warn against them.
# On Hermes versions where --force cannot override DANGEROUS, those attempts
# fail but the script must still verify the actual installed state. The other 18
# stay on the default no-override path.
#
# The post-loop pass derives success from `hermes skills list` rather than the
# per-call exit code: hermes exits 0 even on a BLOCKED verdict, so trusting the
# exit code is the "derive success from a missing error string" anti-pattern.
#
# Usage: bash plugins/sefi-core/scripts/install-hermes.sh [--auto-update]
set -euo pipefail

AUTO_UPDATE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto-update) AUTO_UPDATE=1; shift ;;
    -h|--help) echo "usage: $0 [--auto-update]"; exit 0 ;;
    *) echo "install-hermes.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_LINK_HOPS=0
while SCRIPT_LINK="$(readlink "$SCRIPT_SOURCE" 2>/dev/null)"; do
  SCRIPT_LINK_HOPS=$((SCRIPT_LINK_HOPS + 1))
  [ "$SCRIPT_LINK_HOPS" -le 40 ] || {
    echo "install-hermes.sh: refusing symlink loop while resolving installer path" >&2
    exit 1
  }
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  case "$SCRIPT_LINK" in
    /*) SCRIPT_SOURCE="$SCRIPT_LINK" ;;
    *) SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_LINK" ;;
  esac
done
[ -f "$SCRIPT_SOURCE" ] || {
  echo "install-hermes.sh: installer source does not resolve to a regular file" >&2
  exit 1
}
HERE="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
SKILLS_SRC="$CORE/skills"
PACKAGE_MANIFEST="$HERE/package-manifest.sh"

find_python() {
  # find_python -- print a Python 3.11+ binary name, or nothing. sefi-runtime.py
  # needs 3.11 (datetime.UTC), so the probe matches run-all.sh's floor.
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

REPO="xsefirosus/sefi-agents"
BASE_PATH="plugins/sefi-core/skills"
SKILLS="sefi-orchestration anti-hallucination memory-protocol loop-engineering retro-improve terse-mode frontend-design motion-design swiftui-design expo-native-design design-style-profiles backend-design security-review technical-writing n8n-workflow-design premortem focus release-tracking run-sefi-benchmark systems-audit"
# Known scanner false positives; see comment above.
FORCE_SKILLS="sefi-orchestration security-review"

print_onboarding() {
  cat <<'EOF'
sefi-agents: installation succeeded.
sefi-agents: run /sefi:init once from each project root before the first routed request.
sefi-agents: auto-init is unsafe because installation is user-wide and cannot safely choose or modify a project.
sefi-agents: cross-project memory is optional, local/private, and off by default; /sefi:init asks interactively and keeps it off when unattended.
EOF
}

command -v hermes >/dev/null 2>&1 || {
  echo "install-hermes.sh: hermes CLI not found on PATH" >&2
  exit 1
}

PYBIN="$(find_python)" || {
  echo "install-hermes.sh: Python 3.11+ is required to record and verify the managed runtime" >&2
  exit 2
}
[ -f "$PACKAGE_MANIFEST" ] || {
  echo "install-hermes.sh: package manifest helper missing at $PACKAGE_MANIFEST" >&2
  exit 1
}

CONFIG_PATH="$(hermes config path)" || {
  echo "install-hermes.sh: cannot locate Hermes config path" >&2
  exit 1
}
CONFIG_DIR="$(dirname "$CONFIG_PATH")"
HERMES_SKILLS="$CONFIG_DIR/skills"
RUNTIME="$CONFIG_DIR/sefi-core"
RUNTIME_STATE="missing"
SKILL_BACKUPS=""
SKILL_BACKUPS_ROOT=""
SKILL_BACKUPS_PARENT=""
HERMES_SKILLS_ROOT=""
INSTALL_SUCCEEDED=0

prepare_skill_backups() {
  mkdir -p "$HERMES_SKILLS"
  [ -d "$HERMES_SKILLS" ] && [ ! -L "$HERMES_SKILLS" ] || {
    echo "install-hermes.sh: refusing non-directory skills root $HERMES_SKILLS" >&2
    exit 1
  }
  HERMES_SKILLS_ROOT="$(cd -P "$HERMES_SKILLS" && pwd -P)"
  SKILL_BACKUPS="$(mktemp -d "${TMPDIR:-/tmp}/sefi-hermes-skills.XXXXXX")" || {
    echo "install-hermes.sh: cannot create skill rollback quarantine" >&2
    exit 1
  }
  SKILL_BACKUPS_ROOT="$(cd -P "$SKILL_BACKUPS" && pwd -P)"
  SKILL_BACKUPS_PARENT="$(cd -P "$(dirname "$SKILL_BACKUPS_ROOT")" && pwd -P)"
  for name in $SKILLS; do
    local live="$HERMES_SKILLS_ROOT/$name"
    if [ -L "$live" ]; then
      echo "install-hermes.sh: refusing symlinked live skill $live" >&2
      exit 1
    fi
    if [ -e "$live" ]; then
      [ -d "$live" ] || {
        echo "install-hermes.sh: refusing non-directory live skill $live" >&2
        exit 1
      }
      cp -R "$live" "$SKILL_BACKUPS_ROOT/$name"
    else
      : >"$SKILL_BACKUPS_ROOT/$name.missing"
    fi
  done
}

safe_remove_backup_path() {
  local target="$1" resolved=""
  resolved="$(cd -P "$target" && pwd -P)" || {
    echo "install-hermes.sh: cannot resolve rollback quarantine path $target" >&2
    return 1
  }
  case "$resolved" in
    "$SKILL_BACKUPS_ROOT"/*) rm -rf -- "$resolved" ;;
    *) echo "install-hermes.sh: refusing rollback cleanup outside quarantine: $resolved" >&2; return 1 ;;
  esac
}

safe_remove_live_skill() {
  local name="$1" target="$HERMES_SKILLS_ROOT/$1" parent=""
  parent="$(cd -P "$(dirname "$target")" && pwd -P)" || {
    echo "install-hermes.sh: cannot resolve live skill parent for $name" >&2
    return 1
  }
  [ "$parent" = "$HERMES_SKILLS_ROOT" ] || {
    echo "install-hermes.sh: refusing live skill removal outside skills root: $target" >&2
    return 1
  }
  rm -rf -- "$target"
}

restore_skills() {
  [ -n "$SKILL_BACKUPS_ROOT" ] || return 0
  local name=""
  for name in $SKILLS; do
    safe_remove_live_skill "$name" || return 1
    if [ -d "$SKILL_BACKUPS_ROOT/$name" ]; then
      cp -R "$SKILL_BACKUPS_ROOT/$name" "$HERMES_SKILLS_ROOT/$name" || return 1
    fi
  done
}

cleanup_skill_backups() {
  [ -n "$SKILL_BACKUPS_ROOT" ] || return 0
  if [ "$INSTALL_SUCCEEDED" -ne 1 ]; then
    restore_skills || echo "install-hermes.sh: failed to restore the pre-install skill snapshot" >&2
  fi
  local parent=""
  parent="$(cd -P "$(dirname "$SKILL_BACKUPS_ROOT")" && pwd -P)" || return 1
  [ "$parent" = "$SKILL_BACKUPS_PARENT" ] || return 1
  case "$(basename "$SKILL_BACKUPS_ROOT")" in
    sefi-hermes-skills.*) rm -rf -- "$SKILL_BACKUPS_ROOT" ;;
    *) echo "install-hermes.sh: refusing rollback cleanup outside quarantine: $SKILL_BACKUPS_ROOT" >&2; return 1 ;;
  esac
}

check_runtime() {
  if [ ! -e "$RUNTIME" ]; then return 0; fi
  if [ ! -d "$RUNTIME" ] || [ -L "$RUNTIME" ]; then
    echo "install-hermes.sh: refusing unmanaged runtime path $RUNTIME" >&2
    exit 1
  fi
  local verdict="" rc=0
  verdict="$(bash "$PACKAGE_MANIFEST" diff --root "$CONFIG_DIR" --source "$CORE" --destination "$RUNTIME" 2>&1)" || rc=$?
  case "$verdict" in
    *"package-manifest-diff: current"*) RUNTIME_STATE="current" ;;
    *"package-manifest-diff: stale"*)
      if [ "$AUTO_UPDATE" -eq 1 ]; then
        RUNTIME_STATE="stale"
        echo "install-hermes.sh: --auto-update $verdict; refreshing managed runtime" >&2
      else
        echo "install-hermes.sh: managed runtime differs from this source; rerun with --auto-update" >&2
        exit 1
      fi
      ;;
    *"package-manifest-diff: drift"*)
      echo "install-hermes.sh: --auto-update refused: $verdict" >&2
      exit 1
      ;;
    *)
      echo "install-hermes.sh: cannot classify existing runtime (exit $rc): $verdict" >&2
      exit 1
      ;;
  esac
}

install_runtime() {
  [ "$RUNTIME_STATE" = "current" ] && return 0
  mkdir -p "$RUNTIME"
  "$PYBIN" - "$RUNTIME" "$CORE" "$RUNTIME_STATE" <<'PYEOF'
import hashlib
import json
import sys
from pathlib import Path, PurePosixPath

runtime = Path(sys.argv[1])
source = Path(sys.argv[2])
state = sys.argv[3]
if not runtime.is_dir() or runtime.is_symlink():
    raise SystemExit(f"runtime is not a physical directory: {runtime}")
root = runtime.resolve()

def safe_path(relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise SystemExit(f"unsafe managed runtime path: {relative}")
    candidate = (root / path).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError:
        raise SystemExit(f"managed runtime path escapes its root: {relative}")
    return candidate

def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

new_files: dict[str, str] = {}
for path in sorted(source.rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"source contains symlinked content: {path}")
    if path.is_file():
        relative = path.relative_to(source).as_posix()
        safe_path(relative)
        new_files[relative] = digest(path)

if state == "stale":
    manifest_path = root / ".sefi-agents-manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise SystemExit("managed runtime manifest is unavailable for retirement")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    old_files = manifest.get("managed_files")
    if not isinstance(old_files, dict) or not all(isinstance(key, str) for key in old_files):
        raise SystemExit("managed runtime manifest has invalid managed files")
    retired = sorted(set(old_files) - set(new_files), reverse=True)
    for relative in retired:
        target = safe_path(relative)
        if target.is_symlink():
            raise SystemExit(f"retired managed path is symlinked: {relative}")
        if target.exists():
            if not target.is_file():
                raise SystemExit(f"retired managed path is not a file: {relative}")
            target.unlink()
        parent = target.parent
        while parent != root:
            if parent.is_symlink():
                raise SystemExit(f"managed runtime directory is symlinked: {parent}")
            try:
                parent.rmdir()
            except OSError:
                break
            parent = parent.parent
PYEOF
  # Copying source entries over a verified managed runtime retains unrelated content.
  cp -R "$CORE/." "$RUNTIME/"
  "$PYBIN" - "$RUNTIME" "$CORE" <<'PYEOF'
import hashlib
import sys
from pathlib import Path

runtime = Path(sys.argv[1])
source = Path(sys.argv[2])
if not runtime.is_dir() or runtime.is_symlink():
    raise SystemExit(f"runtime is not a physical directory: {runtime}")
root = runtime.resolve()
for path in sorted(source.rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    relative = path.relative_to(source)
    installed = (root / relative).resolve(strict=False)
    try:
        installed.relative_to(root)
    except ValueError:
        raise SystemExit(f"installed runtime path escapes its root: {relative}")
    if installed.is_symlink() or not installed.is_file():
        raise SystemExit(f"installed runtime file is missing or symlinked: {relative}")
    if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(installed.read_bytes()).digest():
        raise SystemExit(f"installed runtime content differs from source: {relative}")
PYEOF
  bash "$PACKAGE_MANIFEST" create --root "$CONFIG_DIR" --source "$CORE" --destination "$RUNTIME"
  echo "install-hermes.sh: managed runtime installed at $RUNTIME" >&2
}

resolve_audit_contract() {
  local contract="$1"
  "$PYBIN" - "$contract" "$RUNTIME" <<'PYEOF'
from pathlib import Path
import sys
contract = Path(sys.argv[1])
runtime = Path(sys.argv[2])
text = contract.read_text(encoding="utf-8")
runtime_scripts = (runtime / "scripts" / "ci").as_posix() + "/"
text = text.replace("../../../scripts/ci/", runtime_scripts)
text = text.replace("<runtime-root>/scripts/ci/", runtime_scripts)
contract.write_text(text, encoding="utf-8", newline="\n")
PYEOF
}

matches_expected_skill_tree() {
# Git's Windows checkout conversion changes only LF to CRLF. Compare exact file sets and
# bytes first; when Markdown bytes differ, accept only the corresponding CRLF-to-LF
# normalization. Every non-Markdown file remains byte-exact.
  "$PYBIN" - "$1" "$2" <<'PYEOF'
import sys
from pathlib import Path

expected_root = Path(sys.argv[1])
installed_root = Path(sys.argv[2])

def files(root: Path) -> dict[str, bytes]:
    if not root.is_dir() or root.is_symlink():
        raise SystemExit(1)
    result: dict[str, bytes] = {}
    for path in root.rglob("*"):
        if path.is_symlink() or (not path.is_dir() and not path.is_file()):
            raise SystemExit(1)
        if path.is_file():
            result[path.relative_to(root).as_posix()] = path.read_bytes()
    return result

expected = files(expected_root)
installed = files(installed_root)
if expected.keys() != installed.keys():
    raise SystemExit(1)
for relative in expected:
    source = expected[relative]
    fetched = installed[relative]
    if source != fetched and (not relative.endswith(".md") or source.replace(b"\r\n", b"\n") != fetched.replace(b"\r\n", b"\n")):
        raise SystemExit(1)
PYEOF
}

matches_expected_skill() {
  # Accept the source bytes, checkout-only CRLF conversion, or the one documented
  # installed-only rewrite that binds systems-audit's contract to this runtime.
  local name="$1" installed="$2" staged=""
  if matches_expected_skill_tree "$SKILLS_SRC/$name" "$installed"; then return 0; fi
  [ "$name" = "systems-audit" ] || return 1
  staged="$(mktemp -d "$SKILL_BACKUPS_ROOT/staged.XXXXXX")"
  cp -R "$SKILLS_SRC/$name" "$staged/$name"
  resolve_audit_contract "$staged/$name/references/report-contract.md"
  if matches_expected_skill_tree "$staged/$name" "$installed"; then
    safe_remove_backup_path "$staged"
    return 0
  fi
  safe_remove_backup_path "$staged"
  return 1
}

resolve_systems_audit_runtime() {
  local contract="$HERMES_SKILLS/systems-audit/references/report-contract.md"
  [ -f "$contract" ] || {
    echo "install-hermes.sh: systems-audit report contract missing after fetch" >&2
    exit 1
  }
  resolve_audit_contract "$contract"
}

check_runtime
prepare_skill_backups
trap cleanup_skill_backups EXIT

# in_force <name> -- exit 0 if <name> is in FORCE_SKILLS.
in_force() {
  for f in $FORCE_SKILLS; do
    [ "$f" = "$1" ] && return 0
  done
  return 1
}

attempt_fail=0
for name in $SKILLS; do
  echo "=== installing $name ===" >&2
  if in_force "$name"; then
    if hermes skills install "$REPO/$BASE_PATH/$name" --yes --force; then
      :
    else
      echo "FAILED: $name (will verify installed state after all attempts)" >&2
      attempt_fail=$((attempt_fail + 1))
    fi
  else
    if hermes skills install "$REPO/$BASE_PATH/$name" --yes; then
      :
    else
      echo "FAILED: $name (will verify installed state after all attempts)" >&2
      attempt_fail=$((attempt_fail + 1))
    fi
  fi
done

echo >&2
echo "=== verifying via hermes skills list ===" >&2
if [ "$attempt_fail" -ne 0 ]; then
  echo "install-hermes.sh: $attempt_fail install call(s) failed; verifying installed state anyway." >&2
fi

# hermes skills list is a unicode-bordered table. The data lines start with
# U+2502 (vertical box char) + space; the next U+2502 + space ends the name
# column. Use awk with those patterns directly -- a tr-based collapse would map
# each byte of the multi-byte char to the same replacement (3 pipes for one
# glyph), and re-encoding the U+2502 as an ASCII byte sequence keeps this
# script ASCII-only for the repo's check-unicode-safety.sh.
vbar_sp=$(printf '\342\224\202 ')   # U+2502 + space
sp_vbar=$(printf ' \342\224\202')   # space + U+2502
installed_names=$(hermes skills list 2>&1 | awk -v lead="$vbar_sp" -v sep="$sp_vbar" '
  index($0, lead) == 1 {
    line = $0
    sub(lead, "", line)
    i = index(line, sep)
    if (i > 0) line = substr(line, 1, i - 1)
    gsub(/^ +| +$/, "", line)
    # Skip the column header row (its first column is "Name").
    if (line == "Name") next
    print line
  }
')

ok=0
missing=""
content_mismatch=""
for name in $SKILLS; do
  if printf '%s\n' "$installed_names" | grep -qxF "$name"; then
    ok=$((ok + 1))
    # `hermes skills install` can return success for an unexpected revision. Verify the
    # fetched tree before we tailor systems-audit's installed contract to its runtime.
    if ! matches_expected_skill "$name" "$HERMES_SKILLS/$name"; then
      content_mismatch="$content_mismatch $name"
    fi
  else
    missing="$missing $name"
  fi
done

echo >&2
if [ -n "$missing" ]; then
  echo "install-hermes.sh: $ok of 20 installed. Missing:$missing" >&2
  echo "install-hermes.sh: no managed runtime was updated; resolve the fetch failure and rerun." >&2
  exit 1
fi
if [ -n "$content_mismatch" ]; then
  echo "install-hermes.sh: fetched skill content differs from the expected source:$content_mismatch; refusing success." >&2
  exit 1
fi
install_runtime
resolve_systems_audit_runtime
INSTALL_SUCCEEDED=1
if [ "$RUNTIME_STATE" = "current" ]; then
  echo "install-hermes.sh: managed runtime is current; nothing to do." >&2
else
  echo "install-hermes.sh: all $ok of 20 skills installed with verified source bytes and managed runtime $RUNTIME." >&2
fi
print_onboarding
