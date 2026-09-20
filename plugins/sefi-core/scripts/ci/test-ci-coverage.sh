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
grep -Fq 'test-v08-durability.sh' "$RUN_ALL" || {
  echo "FAIL: run-all.sh must execute v0.8 durability regressions" >&2
  exit 1
}
grep -Fq 'test-v08-conformance.sh' "$RUN_ALL" || {
  echo "FAIL: run-all.sh must execute v0.8 behavior conformance regressions" >&2
  exit 1
}
for v08_test in test-memory-journalist.sh test-onboarding-v08.sh test-agent-capabilities-v08.sh; do
  grep -Fq "$v08_test" "$RUN_ALL" || {
    echo "FAIL: run-all.sh must execute $v08_test" >&2
    exit 1
  }
done

for v09_test in test-design-council.sh test-design-council-routing.sh test-v09-documentation.sh; do
  grep -Fq "$v09_test" "$RUN_ALL" || {
    echo "FAIL: run-all.sh must execute $v09_test" >&2
    exit 1
  }
done
