#!/usr/bin/env bash
# Keep CI's top-level entry point aligned with the repository's executable surfaces.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUN_ALL="$ROOT/plugins/sefi-core/scripts/ci/run-all.sh"

grep -Fq -- '-m unittest discover -s benchmarks -p' "$RUN_ALL" || {
  echo "FAIL: run-all.sh must execute benchmark unit tests" >&2
  exit 1
}
grep -Fq 'git ls-files' "$RUN_ALL" || {
  echo "FAIL: run-all.sh must syntax-check every tracked shell script" >&2
  exit 1
}
grep -Fq 'test-workflow-safety.sh' "$RUN_ALL" || {
  echo "FAIL: run-all.sh must execute workflow safety regressions" >&2
  exit 1
}
