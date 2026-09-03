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
  # _run <budget-seconds> <label> [--tolerate=<space-sep-codes>] <cmd...>
  # Never aborts; records the worst exit code. A tolerated exit code does not redden the
  # gate (used for pytest's exit 5 "no tests collected" when a config section forces an
  # unconditional run).
  local budget="$1" label="$2"
  shift 2
  local tolerate=""
  case "${1:-}" in
    --tolerate=*) tolerate="${1#--tolerate=}"; shift ;;
  esac
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
  if [ -n "$tolerate" ]; then
    case " $tolerate " in
      *" $code "*)
        [ "$code" -ne 0 ] && echo "gate: $label exit $code tolerated (not a gate failure)" >&2
        code=0
        ;;
    esac
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
  if command -v pytest >/dev/null 2>&1; then
    # If the project declares an explicit pytest config section, its `python_files` /
    # `testpaths` may point discovery at non-default filenames the pattern probe below
    # would miss. In that case run pytest UNCONDITIONALLY and treat ONLY exit 5 ("no
    # tests collected") as non-fatal. Otherwise keep the filename-pattern guard: `pytest`
    # against a repo with *.py source but no test files exits 5, which the aggregator
    # would otherwise record as a red gate for a repo that never claimed a suite.
    # A pytest config section can live in any of four files -- pyproject.toml, pytest.ini,
    # tox.ini, or setup.cfg -- and tox.ini is a first-class pytest config location, not an
    # afterthought. Both branches keep the .git / .worktrees exclusions: an unconditional
    # `pytest -q` from the repo root would otherwise recurse into a sibling worktree under
    # .worktrees/ and collect its suite as if it were this project's.
    pytest_cfg=0
    [ -f pyproject.toml ] && grep -q '^\[tool\.pytest\.ini_options\]' pyproject.toml 2>/dev/null && pytest_cfg=1
    [ -f pytest.ini ]     && grep -q '^\[pytest\]' pytest.ini 2>/dev/null && pytest_cfg=1
    [ -f tox.ini ]        && grep -q '^\[pytest\]' tox.ini 2>/dev/null && pytest_cfg=1
    [ -f setup.cfg ]      && grep -q '^\[tool:pytest\]' setup.cfg 2>/dev/null && pytest_cfg=1
    if [ "$pytest_cfg" -eq 1 ]; then
      _run "$TIMEOUT_TEST" "pytest" --tolerate=5 pytest -q --ignore=.git --ignore=.worktrees
    elif find . \
         \( -name 'conftest.py' -o -name 'test_*.py' -o -name '*_test.py' \) \
         -not -path './.git/*' -not -path './.worktrees/*' \
         -print -quit 2>/dev/null | grep -q .; then
      run_test "pytest" pytest -q --ignore=.git --ignore=.worktrees
    fi
  fi
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
