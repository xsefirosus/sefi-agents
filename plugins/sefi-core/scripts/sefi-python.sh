#!/usr/bin/env bash
# sefi-python.sh -- sourceable helper: resolve a MSYS-safe Python interpreter.
#
# Every sefi script needs Python 3.11+ (datetime.UTC) and every one of them
# resolves it by looping over python3/python. That loop is fine on POSIX hosts
# and broken under git-bash on Windows, where bash-resolved paths handed to a
# native Windows Python come back as \c\Users\... and every script exits 2
# before it can judge anything. Live-confirmed 2026-10-03: one such bug
# produced 100+ unrelated-looking CI failures.
#
# sefi_python_bin prints the wrapper on MSYS hosts and the plain interpreter
# elsewhere, so callers keep their existing "$PYBIN -" call sites unchanged:
#
#   . "$(dirname "$0")/sefi-python.sh"
#   PYBIN="$(sefi_python_bin)" || exit 2
#
# Sourcing this file has no side effects beyond defining the function.
sefi_python_bin() {
  local here wrapper
  here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  wrapper="$here/sefi-python"

  # Only an MSYS/Cygwin host needs the wrapper. Elsewhere a wrapper would be a
  # harmless extra process, but skipping it keeps POSIX behavior byte-identical.
  if command -v cygpath >/dev/null 2>&1 && [ -f "$wrapper" ]; then
    printf '%s\n' "$wrapper"
    return 0
  fi

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
