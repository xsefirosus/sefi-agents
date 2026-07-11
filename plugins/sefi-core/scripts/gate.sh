#!/usr/bin/env bash
# gate.sh -- deterministic quality gate for the current project. Detects project type,
# runs formatter/linter/tests when present, routes each tool's output through
# compress-output.sh, and exits nonzero on any failure. Preserves the failing exit code.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
COMPRESS="$HERE/compress-output.sh"

overall=0
ran=0

run() {
  # run <label> <cmd...> -- never aborts; records the worst exit code seen.
  ran=$((ran + 1))
  local label="$1"
  local code=0
  if [ -x "$COMPRESS" ] || [ -f "$COMPRESS" ]; then
    bash "$COMPRESS" "$@" || code=$?
  else
    shift
    echo "gate: $label (no compressor; running direct)" >&2
    "$@" || code=$?
  fi
  [ "$code" -ne 0 ] && overall="$code"
  return 0
}

# --- Node ---
if [ -f package.json ]; then
  if command -v npm >/dev/null 2>&1; then
    grep -q '"lint"' package.json && run "npm-lint" npm run -s lint
    grep -q '"test"' package.json && run "npm-test" npm test --silent
  fi
fi

# --- Python ---
if [ -f pyproject.toml ] || [ -f requirements.txt ] || ls ./*.py >/dev/null 2>&1; then
  command -v ruff >/dev/null 2>&1 && run "ruff" ruff check .
  command -v pytest >/dev/null 2>&1 && run "pytest" pytest -q
fi

# --- Rust ---
if [ -f Cargo.toml ]; then
  command -v cargo >/dev/null 2>&1 && run "cargo-test" cargo test --quiet
fi

# --- Go ---
if [ -f go.mod ]; then
  command -v go >/dev/null 2>&1 && run "go-test" go test ./...
fi

# --- Shell ---
if command -v shellcheck >/dev/null 2>&1; then
  sh_files="$(ls ./*.sh 2>/dev/null || true)"
  [ -n "$sh_files" ] && run "shellcheck" shellcheck $sh_files
fi

if [ "$ran" -eq 0 ]; then
  echo "gate: no known toolchain detected; nothing to run (pass)" >&2
  exit 0
fi

if [ "$overall" -ne 0 ]; then
  echo "gate: FAILED (exit $overall)" >&2
  exit "$overall"
fi
echo "gate: PASSED ($ran checks)" >&2
exit 0
