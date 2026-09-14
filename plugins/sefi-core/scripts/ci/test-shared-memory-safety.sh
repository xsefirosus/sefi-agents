#!/usr/bin/env bash
# Focused regression coverage for the shared-memory mirror boundary. This test owns all
# of its state under one disposable directory and never touches a real user mirror.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
RESOLVE="$CORE/resolve-shared-memory-path.sh"
WRITE="$CORE/write-shared-memory-mirror.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-shared-memory.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
HOME_ROOT="$TMP/home"
WORKSPACE="$TMP/workspace"
mkdir -p "$BIN" "$HOME_ROOT" "$WORKSPACE/.sefi"

cat > "$BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' MINGW64_NT-10.0
EOF
cat > "$BIN/systemd-detect-virt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' none
EOF
cat > "$BIN/date" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 2030-01-02-0304
EOF
chmod +x "$BIN/uname" "$BIN/systemd-detect-virt" "$BIN/date"

clean_env=(env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX \
  PATH="$BIN:$PATH" HOME="$HOME_ROOT")

resolved="$(cd "$WORKSPACE" && "${clean_env[@]}" bash "$RESOLVE")"
expected_root="$(cd "$HOME_ROOT" && pwd -P)/sefi-memory"
[ "$resolved" = "$expected_root" ] || {
  echo "expected per-user mirror root $expected_root, got $resolved" >&2
  exit 1
}
if cd "$WORKSPACE" && env -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX \
  CI=true PATH="$BIN:$PATH" HOME="$HOME_ROOT" bash "$RESOLVE" >/dev/null 2>&1; then
  echo 'CI environment unexpectedly resolved a mirror root' >&2
  exit 1
fi
mkdir "$WORKSPACE/config"
printf 'memory:\n  cross_project_enabled: false\n' > "$WORKSPACE/config/sefi.config.yml"
if cd "$WORKSPACE" && "${clean_env[@]}" bash "$RESOLVE" >/dev/null 2>&1; then
  echo 'disabled mirror unexpectedly resolved a path' >&2
  exit 1
fi
rm -rf "$WORKSPACE/config"

printf 'safe note\n' > "$WORKSPACE/note.md"
printf 'known-harness\n' > "$WORKSPACE/.sefi/harness"
dest1="$(cd "$WORKSPACE" && "${clean_env[@]}" bash "$WRITE" 'topic' note.md)"
dest2="$(cd "$WORKSPACE" && "${clean_env[@]}" bash "$WRITE" 'topic' note.md)"
[ "$dest1" != "$dest2" ] || { echo 'same-minute writes must be unique' >&2; exit 1; }
[ ! -L "$dest1" ] && [ ! -L "$dest2" ] || { echo 'mirror write created a symlink' >&2; exit 1; }
[ "$(cat "$dest1")" = 'safe note' ] || { echo 'first mirror write was overwritten' >&2; exit 1; }
[ "$(cat "$dest2")" = 'safe note' ] || { echo 'second mirror write lost content' >&2; exit 1; }

git -C "$WORKSPACE" init -q
git -C "$WORKSPACE" remote add origin 'https://ghp_EXAMPLESECRET@github.com/acme/repo.git'
credential_dest="$(cd "$WORKSPACE" && "${clean_env[@]}" bash "$WRITE" 'credential-check' note.md)"
case "$credential_dest" in
  *ghp*|*EXAMPLESECRET*) echo 'credential-bearing remote leaked into mirror path' >&2; exit 1 ;;
esac

printf '../../escaped\n' > "$WORKSPACE/.sefi/harness"
if cd "$WORKSPACE" && "${clean_env[@]}" bash "$WRITE" 'topic' note.md >/dev/null 2>&1; then
  echo 'unsafe harness value was accepted' >&2
  exit 1
fi
[ ! -e "$TMP/escaped" ] || { echo 'unsafe harness escaped the mirror root' >&2; exit 1; }

printf 'known-harness\n' > "$WORKSPACE/.sefi/harness"
outside="$TMP/outside"
mkdir "$outside"
linked_home="$TMP/linked-home"
mkdir "$linked_home"
ln -s "$outside" "$linked_home/sefi-memory"
if [ -L "$linked_home/sefi-memory" ]; then
  if cd "$WORKSPACE" && env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX \
    PATH="$BIN:$PATH" HOME="$linked_home" bash "$WRITE" 'topic' note.md >/dev/null 2>&1; then
    echo 'symlink mirror root was accepted' >&2
    exit 1
  fi
  [ -z "$(find "$outside" -mindepth 1 -print -quit)" ] || {
    echo 'symlink mirror root received a mirror write' >&2
    exit 1
  }

  project_dir="$(dirname "$dest1")"
  rm -f -- "$dest1" "$dest2"
  rmdir "$project_dir"
  ln -s "$outside" "$project_dir"
  if cd "$WORKSPACE" && "${clean_env[@]}" bash "$WRITE" 'topic' note.md >/dev/null 2>&1; then
    echo 'symlink project destination was accepted' >&2
    exit 1
  fi
  [ -z "$(find "$outside" -mindepth 1 -print -quit)" ] || {
    echo 'symlink destination received a mirror write' >&2
    exit 1
  }
else
  echo 'test-shared-memory-safety: SKIP symlink checks (host cannot create symlinks)'
fi

echo 'test-shared-memory-safety: OK'
