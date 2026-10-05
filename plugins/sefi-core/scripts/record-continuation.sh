#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Resolve through sefi-python.sh. A bare `command -v python3` under git-bash yields
# a native interpreter, which then receives "$HERE/sefi-runtime.py" as an MSYS path
# and dies with "can't open file 'C:\\c\\Users\\...'". The shared resolver returns the
# path-translating wrapper on MSYS hosts and plain python3 on POSIX, so this is a
# no-op everywhere except where the bug actually was.
# shellcheck source=sefi-python.sh
. "$HERE/sefi-python.sh"
if python_bin="$(sefi_python_bin 2>/dev/null)" \
  && [ -n "$python_bin" ] && "$python_bin" -c 'import sys' >/dev/null 2>&1; then
  exec "$python_bin" "$HERE/sefi-runtime.py" continuation "$@"
fi
echo 'record-continuation: Python is required' >&2
exit 1
