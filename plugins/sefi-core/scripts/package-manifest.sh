#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# MSYS-safe interpreter. package-manifest is the one script that execs Python
# outright, and it is what records source_version/source_commit for both
# installers. Under git-bash on Windows the unwrapped interpreter could not read
# the git paths it was handed, so every recorded field came back UNKNOWN and
# both installers reported their runtime as unclassifiable (live-confirmed
# 2026-10-03). See scripts/sefi-python.sh.
. "$HERE/sefi-python.sh"
python_bin="$(sefi_python_bin)" || {
  echo 'package-manifest: Python 3.11+ is required' >&2
  exit 2
}
exec "$python_bin" "$HERE/sefi-runtime.py" manifest "$@"
