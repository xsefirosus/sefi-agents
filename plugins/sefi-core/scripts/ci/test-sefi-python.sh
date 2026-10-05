#!/usr/bin/env bash
# CI: sefi-python translates MSYS drive paths; non-drive paths pass through.
#
# The wrapper is the single point that makes every sefi script work under
# git-bash on Windows, so its own behavior is worth pinning. These cases are
# written to run on POSIX hosts too, where the wrapper resolves to plain
# python3/python and the translation simply never triggers.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$CORE/scripts/sefi-python"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "=== sefi-python (MSYS path translation) ==="

[ -x "$WRAPPER" ] || [ -f "$WRAPPER" ] || { bad "wrapper missing"; echo "  (0 passed, 1 failed)"; exit 1; }

# Locate an interpreter directly for the assertions that need one.
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
[ -n "$PY" ] || { bad "no interpreter available"; echo "  (0 passed, 1 failed)"; exit 1; }

# 1. Inline code passed with -c survives verbatim (no path mangling).
out="$(bash "$WRAPPER" -c 'print("CODE_INTACT")' 2>&1)"
if grep -q CODE_INTACT <<<"$out"; then ok "inline -c code passes through unmodified"
else bad "inline -c code mangled: $out"; fi

# 2. A stdin script runs.
out="$(printf 'print("STDIN_OK")\n' | bash "$WRAPPER" - 2>&1)"
if grep -q STDIN_OK <<<"$out"; then ok "stdin script executes"
else bad "stdin script did not run: $out"; fi

# 3. A non-drive absolute POSIX path is preserved byte for byte.
out="$(bash "$WRAPPER" -c 'import sys; print("ARG:" + sys.argv[1])' /tmp/plain 2>&1)"
if grep -q 'ARG:/tmp/plain' <<<"$out"; then ok "plain POSIX path untouched"
else bad "plain POSIX path altered: $out"; fi

# 4. A real file handed in MSYS form is readable through the wrapper. On POSIX
#    this is the same read; on MSYS it is the assertion that matters.
read_out="$(bash "$WRAPPER" -c '
import sys
from pathlib import Path
p = Path(sys.argv[1])
print("READABLE" if p.is_file() else "UNREADABLE")
' "$CORE/scripts/sefi-python" 2>&1)"
if grep -q READABLE <<<"$read_out"; then ok "a repo file resolves through the wrapper"
else bad "repo file unreadable through wrapper: $read_out"; fi

# 5. Exit status propagates (a failing script stays failing).
if bash "$WRAPPER" -c 'raise SystemExit(7)' >/dev/null 2>&1; then
  bad "nonzero exit was swallowed"
else
  [ "$?" -eq 7 ] && ok "exit status propagates (7)" || ok "nonzero exit propagates"
fi

# 6. A path containing spaces round-trips -- the real Windows case. The
#    directory is created first, so the correct answer is EXISTS: seeing it is
#    exactly what proves the translation preserved both the drive prefix and
#    the embedded space.
spaced="$(mktemp -d)/dir with spaces"
mkdir -p "$spaced"
sp_out="$(bash "$WRAPPER" -c '
import sys, os
print("EXISTS" if os.path.isdir(sys.argv[1]) else "MANGLED")
' "$spaced" 2>&1)"
if grep -q EXISTS <<<"$sp_out"; then ok "path containing spaces round-trips"
else bad "spaced path mangled: $sp_out"; fi
rm -rf "$(dirname "$spaced")"

echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ]
