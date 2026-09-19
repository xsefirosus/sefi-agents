#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for python_bin in python3 python; do
  if command -v "$python_bin" >/dev/null 2>&1 \
    && "$python_bin" -c 'import sys' >/dev/null 2>&1; then
    exec "$python_bin" "$HERE/sefi-runtime.py" manifest "$@"
  fi
done
echo 'package-manifest: Python is required' >&2
exit 1
