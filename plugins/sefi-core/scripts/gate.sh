#!/usr/bin/env bash
# gate.sh -- deterministic quality gate for the current project. Detects project type,
# runs formatter/linter/typechecker/tests when present, routes each tool's output through
# compress-output.sh, and exits nonzero on any failure. Preserves the failing exit code.
#
# Per-operation timeout classes (loop-engineering skill, "Four predecessor-earned rules"):
# a long legitimate operation gets its own larger budget, not the default. A 300s default
# once killed a live 12-task dispatch; the fix was a separate budget for that call class.
# Two classes ship here -- default (lint/format/typecheck) and test (suites, which are the
# long legitimate operation). Override with SEFI_GATE_TIMEOUT / SEFI_GATE_TEST_TIMEOUT.
# When no timeout binary exists the gate says so out loud rather than implying a bound it
# is not enforcing.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
COMPRESS="$HERE/compress-output.sh"

TIMEOUT_DEFAULT="${SEFI_GATE_TIMEOUT:-300}"
TIMEOUT_TEST="${SEFI_GATE_TEST_TIMEOUT:-900}"

# GNU coreutils `timeout`; `gtimeout` on macOS with coreutils installed.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "gate: no timeout binary on PATH; running WITHOUT a time bound (a hung check will hang this gate)" >&2
fi

overall=0
ran=0

_run() {
  # _run <budget-seconds> <label> <cmd...> -- never aborts; records the worst exit code.
  local budget="$1" label="$2"
  shift 2
  ran=$((ran + 1))
  local code=0
  if [ -f "$COMPRESS" ]; then
    if [ -n "$TIMEOUT_BIN" ]; then
      bash "$COMPRESS" "$label" "$TIMEOUT_BIN" "$budget" "$@" || code=$?
    else
      bash "$COMPRESS" "$label" "$@" || code=$?
    fi
  else
    echo "gate: $label (no compressor; running direct)" >&2
    if [ -n "$TIMEOUT_BIN" ]; then
      "$TIMEOUT_BIN" "$budget" "$@" || code=$?
    else
      "$@" || code=$?
    fi
  fi
  # 124 is coreutils timeout's "killed on expiry". Name it: a bare exit 124 in a log reads
  # as an ordinary tool failure and sends the reader hunting for a bug that is not there.
  if [ "$code" -eq 124 ]; then
    echo "gate: TIMEOUT $label exceeded ${budget}s (class budget; raise via SEFI_GATE_TIMEOUT / SEFI_GATE_TEST_TIMEOUT)" >&2
  fi
  [ "$code" -ne 0 ] && overall="$code"
  return 0
}

run()      { _run "$TIMEOUT_DEFAULT" "$@"; }   # lint / format / typecheck class
run_test() { _run "$TIMEOUT_TEST" "$@"; }      # long-operation class (suites)

has_script() {
  # has_script <name> -- package.json declares this npm script.
  grep -q "\"$1\"[[:space:]]*:" package.json 2>/dev/null
}

# --- Node ---
if [ -f package.json ]; then
  # Respect the project's actual package manager; a bare `npm` in a pnpm/yarn/bun repo
  # either fails on a missing lockfile or silently resolves a different dependency tree.
  PM=""
  if   [ -f pnpm-lock.yaml ]   && command -v pnpm >/dev/null 2>&1; then PM="pnpm"
  elif [ -f yarn.lock ]        && command -v yarn >/dev/null 2>&1; then PM="yarn"
  elif [ -f bun.lockb ]        && command -v bun  >/dev/null 2>&1; then PM="bun"
  elif command -v npm >/dev/null 2>&1; then PM="npm"
  fi
  if [ -n "$PM" ]; then
    has_script lint      && run      "$PM-lint"      "$PM" run -s lint
    has_script typecheck && run      "$PM-typecheck" "$PM" run -s typecheck
    # `npm test --silent` passes --silent to the TEST SCRIPT, not to npm. `run -s test`
    # silences the runner, which is what was intended.
    has_script test      && run_test "$PM-test"      "$PM" run -s test
  fi
fi

# --- Python ---
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ] \
   || find . -name '*.py' -not -path './.git/*' -not -path './.worktrees/*' \
        -print -quit 2>/dev/null | grep -q .; then
  command -v ruff   >/dev/null 2>&1 && run      "ruff"   ruff check .
  command -v mypy   >/dev/null 2>&1 && [ -f pyproject.toml ] && run "mypy" mypy .
  command -v pytest >/dev/null 2>&1 && run_test "pytest" pytest -q
fi

# --- Rust ---
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  run      "cargo-fmt"  cargo fmt --check
  run_test "cargo-test" cargo test --quiet
fi

# --- Go ---
if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  run      "go-vet"  go vet ./...
  run_test "go-test" go test ./...
fi

# --- Shell ---
# The old glob was `ls ./*.sh` -- unquoted and top-level only, so a repo whose scripts live
# in scripts/ or plugins/**/scripts/ (this one included) linted exactly nothing.
if command -v shellcheck >/dev/null 2>&1; then
  sh_files=()
  while IFS= read -r s; do sh_files+=("$s"); done < <(
    find . -type f -name '*.sh' \
      -not -path './.git/*' -not -path './.worktrees/*' \
      -not -path './node_modules/*' -not -path './vendor/*' 2>/dev/null | LC_ALL=C sort
  )
  [ "${#sh_files[@]}" -gt 0 ] && run "shellcheck" shellcheck "${sh_files[@]}"
fi

# --- Make (last: only when nothing else claimed the repo) ---
if [ "$ran" -eq 0 ] && [ -f Makefile ] && command -v make >/dev/null 2>&1; then
  grep -qE '^test:' Makefile && run_test "make-test" make test
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
