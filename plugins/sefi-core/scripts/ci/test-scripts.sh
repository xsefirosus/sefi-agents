#!/usr/bin/env bash
# test-scripts.sh -- regression checks for the behavior scripts. Every assertion targets a
# specific failure mode found in the 2026-07-16 behavioral audit, per qa-engineer.md item 6
# ("Every fix you PASS must leave a regression test that asserts the specific failure mode
# traced during the fix") and software-engineer.md item 6 ("Non-trivial logic must leave one
# runnable check behind"). Not a smoke test: each case names the gap it guards.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
BUDGET_TPL="$CORE/templates/config/budget.yml"

fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

expect_code() {
  # expect_code <expected-exit> <label> <cmd...>
  local want="$1" label="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then ok "$label (exit $got)"; else bad "$label (expected exit $want, got $got)"; fi
}

echo "=== budget-check.sh (audit gap 8.1: the fail-open) ==="

# The fix: no ccusage AND no --spent means there is no spend source, so the cap cannot be
# checked and the gate must fail -- now with exit 3 (CANNOT MEASURE), distinct from exit 1
# (EXCEEDED). A caller reading only the exit code could not previously tell "you blew the
# budget" from "the telemetry is broken". Skipped when ccusage is installed locally; CI has
# no ccusage, and CI is the authority for this assertion.
if command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  echo "  SKIP: no-spend-source assertion (ccusage present locally; CI has none)"
else
  expect_code 3 "no ccusage + no --spent exits 3 (CANNOT MEASURE, not EXCEEDED)" \
    bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"
fi

# An explicit --spent 0 is a real claim of zero spend and must still pass.
expect_code 0 "explicit --spent 0 still passes" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 0 --config "$BUDGET_TPL"

# The pre-existing over-cap path must not regress: 3.00 against the template's 2.00 daily.
expect_code 1 "--spent 3.00 over the 2.00 daily cap exits nonzero" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 3.00 --config "$BUDGET_TPL"

# A non-numeric figure must be rejected as a usage error, never coerced to 0 by awk.
expect_code 2 "--spent abc is a usage error, not a silent zero" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent abc --config "$BUDGET_TPL"
expect_code 2 "--pending 1.2.3 is a usage error" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 0 --pending 1.2.3 --config "$BUDGET_TPL"

# --pending must catch an overrun BEFORE it happens: 1.90 spent + 0.50 pending > 2.00 cap.
expect_code 1 "--pending pushes a within-cap spend over the cap" \
  bash "$CORE/scripts/budget-check.sh" --scope daily --spent 1.90 --pending 0.50 --config "$BUDGET_TPL"

# The SECOND fail-open, found 2026-08-11: ccusage present but returning null/empty/crashing.
# The old code assigned that straight to `spent`, and `awk -v s="null" '{print s+0}'` is 0 --
# so a broken telemetry source silently certified every cap as within budget. Stub ccusage
# and jq onto PATH to prove each unusable shape now fails closed.
FAKEBIN="$(mktemp -d)"
mkfake() {
  # mkfake <ccusage-body> <jq-body>
  printf '#!/bin/sh\n%s\n' "$1" > "$FAKEBIN/ccusage"
  printf '#!/bin/sh\ncat >/dev/null\n%s\n' "$2" > "$FAKEBIN/jq"
  chmod +x "$FAKEBIN/ccusage" "$FAKEBIN/jq"
}

mkfake 'echo "{}"' 'echo null'
expect_code 3 "ccusage returning null fails closed (was: coerced to 0 and passed)" \
  env PATH="$FAKEBIN:$PATH" bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"

mkfake 'exit 1' 'echo 0'
expect_code 3 "a crashing ccusage fails closed" \
  env PATH="$FAKEBIN:$PATH" bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"

mkfake 'echo "{}"' 'echo ""'
expect_code 3 "ccusage returning an empty figure fails closed" \
  env PATH="$FAKEBIN:$PATH" bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"

# A broken ccusage must still defer to an explicit caller claim rather than hard-failing.
mkfake 'echo "{}"' 'echo null'
expect_code 0 "a broken ccusage falls back to an explicit --spent" \
  env PATH="$FAKEBIN:$PATH" bash "$CORE/scripts/budget-check.sh" --scope daily --spent 0 --config "$BUDGET_TPL"

# And a WORKING ccusage must still be read and still enforce the cap.
mkfake 'echo "{}"' 'echo 5.00'
expect_code 1 "a working ccusage over the cap still exits EXCEEDED" \
  env PATH="$FAKEBIN:$PATH" bash "$CORE/scripts/budget-check.sh" --scope daily --config "$BUDGET_TPL"
rm -rf "$FAKEBIN"

echo
echo "=== gate.sh (2026-08-11 audit: no timeout, wrong npm flag, top-level-only shellcheck) ==="

GW="$(mktemp -d)"

# The two exact strings qa-engineer.md item 2 distinguishes between. If either is reworded,
# the qa-engineer's "nothing was checked" vs "something passed" rule silently stops working.
gate_out="$( cd "$GW" && bash "$CORE/scripts/gate.sh" 2>&1 )" || true
case "$gate_out" in
  *"no known toolchain detected"*) ok "empty project still reports 'no known toolchain detected'" ;;
  *) bad "the no-toolchain string qa-engineer.md item 2 keys on has changed" ;;
esac

mkdir -p "$GW/node"
printf '{"name":"x","scripts":{"lint":"true","typecheck":"true","test":"true"}}' > "$GW/node/package.json"
gate_out="$( cd "$GW/node" && bash "$CORE/scripts/gate.sh" 2>&1 )" || true
case "$gate_out" in
  *"PASSED (3 checks)"*) ok "lint + typecheck + test all run and report 'PASSED (N checks)'" ;;
  *) bad "expected 'PASSED (3 checks)', got: $(printf '%s' "$gate_out" | tail -1)" ;;
esac

# A failing check must propagate its own exit code, not a generic 1.
printf '{"name":"x","scripts":{"test":"exit 7"}}' > "$GW/node/package.json"
expect_code 7 "a failing check preserves its exit code" \
  bash -c "cd '$GW/node' && bash '$CORE/scripts/gate.sh'"

# The timeout class: before this fix gate.sh had no time bound at all, so a hung suite hung
# the loop forever -- the same failure shape as the predecessor's browser tool eating a
# 50-iteration retry budget. Skipped when no timeout binary exists (the script says so
# itself in that case rather than implying a bound).
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  printf '{"name":"x","scripts":{"test":"sleep 30"}}' > "$GW/node/package.json"
  gate_out="$( cd "$GW/node" && SEFI_GATE_TEST_TIMEOUT=2 bash "$CORE/scripts/gate.sh" 2>&1 )" || true
  case "$gate_out" in
    *"TIMEOUT npm-test exceeded 2s"*) ok "a hung suite is killed by its class budget and named as a TIMEOUT" ;;
    *) bad "expected a named TIMEOUT line, got: $(printf '%s' "$gate_out" | tail -1)" ;;
  esac
else
  echo "  SKIP: timeout assertion (no timeout/gtimeout binary on PATH)"
fi

# shellcheck must reach nested scripts. The old `ls ./*.sh` glob was top-level only, so
# this repo's own 20 scripts under plugins/sefi-core/scripts/ were never linted by its gate.
if command -v shellcheck >/dev/null 2>&1; then
  mkdir -p "$GW/nested/deep/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$GW/nested/deep/scripts/ok.sh"
  gate_out="$( cd "$GW/nested" && bash "$CORE/scripts/gate.sh" 2>&1 )" || true
  case "$gate_out" in
    *shellcheck*) ok "shellcheck reaches a nested scripts/ directory" ;;
    *) bad "shellcheck did not run on a nested .sh file" ;;
  esac
else
  echo "  SKIP: nested-shellcheck assertion (shellcheck not on PATH)"
fi
rm -rf "$GW"

echo
echo "=== gate.sh Python pytest-config detection (Phase-4 FIX 11: fail-open guard) ==="

# gate.sh's round-3 change let an explicit pytest config section force an unconditional
# `pytest -q`. FIX 11 hardens three specific gaps in that branch:
#   (1) a repo with .py source but NO tests and NO config must still stay green (the
#       round-2 filename guard -- qa confirmed this half was NOT the regression);
#   (2) `[tool.pytest.ini_options]` pointing discovery at non-default filenames must
#       actually catch a failing test (not be skipped by the filename guard);
#   (3) tox.ini `[pytest]` is a real pytest config location and must be honored too --
#       the round-3 change only covered pyproject.toml / pytest.ini / setup.cfg.
if command -v pytest >/dev/null 2>&1; then
  GP="$(mktemp -d)"

  # (1) .py source, no tests, no config -> pytest never runs -> gate green.
  mkdir -p "$GP/nosuite"
  printf 'x = 1\n' > "$GP/nosuite/mod.py"
  expect_code 0 "a repo with .py source but no tests and no pytest config passes the gate" \
    bash -c "cd '$GP/nosuite' && bash '$CORE/scripts/gate.sh'"

  # (2) [tool.pytest.ini_options] with python_files pointing at a non-default name; a
  #     failing test under that name must redden the gate.
  mkdir -p "$GP/pyproj"
  printf '[tool.pytest.ini_options]\npython_files = ["spec_*.py"]\n' > "$GP/pyproj/pyproject.toml"
  printf 'def test_it():\n    assert False\n' > "$GP/pyproj/spec_thing.py"
  gp_code=0
  ( cd "$GP/pyproj" && bash "$CORE/scripts/gate.sh" ) >/dev/null 2>&1 || gp_code=$?
  if [ "$gp_code" -ne 0 ]; then
    ok "[tool.pytest.ini_options] + a failing non-default-named test reddens the gate (exit $gp_code)"
  else
    bad "[tool.pytest.ini_options] failing test did NOT redden the gate (exit 0)"
  fi

  # (3) same, but the config section lives in tox.ini [pytest].
  mkdir -p "$GP/toxcfg"
  printf '[pytest]\npython_files = spec_*.py\n' > "$GP/toxcfg/tox.ini"
  printf 'def test_it():\n    assert False\n' > "$GP/toxcfg/spec_thing.py"
  tx_code=0
  ( cd "$GP/toxcfg" && bash "$CORE/scripts/gate.sh" ) >/dev/null 2>&1 || tx_code=$?
  if [ "$tx_code" -ne 0 ]; then
    ok "tox.ini [pytest] + a failing non-default-named test reddens the gate (exit $tx_code)"
  else
    bad "tox.ini [pytest] failing test did NOT redden the gate (exit 0) -- config location not honored"
  fi

  rm -rf "$GP"
else
  echo "  SKIP: gate.sh pytest-config assertions (pytest not on PATH)"
fi

echo
echo "=== validate-no-personal-paths.sh benchmarks/ scan (Phase-4 FIX 12: bytecode + results/ exclusions) ==="

# FIX 12: a synthetic benchmarks/__pycache__/PROBE.pyc carrying a Windows home path must
# NOT trip the scan (bytecode is a compiler artifact, git-ignored, never shipped), and
# the same for anything under the git-ignored benchmarks/results/. Without the exclusions
# on the find line the identical tree DOES trip -- so the exclusion is load-bearing on a
# home-directory checkout, and this pins that it is exactly an exclusion, not a broader
# claim that a real leak ever shipped.
VNP="$CORE/scripts/ci/validate-no-personal-paths.sh"
NPT="$(mktemp -d)"
mkdir -p "$NPT/plugins/sefi-core/scripts/ci" "$NPT/benchmarks/__pycache__" "$NPT/benchmarks/results/2026-01-01-run"
printf 'byte-compiled from C:\\Users\\someone\\proj\\benchmarks\\scorecard.py\n' > "$NPT/benchmarks/__pycache__/PROBE.pyc"
printf 'raw artifact path C:\\Users\\someone\\run\n' > "$NPT/benchmarks/results/2026-01-01-run/raw.txt"
printf '{"clean": true}\n' > "$NPT/benchmarks/fixtures-ok.json"
cp "$VNP" "$NPT/plugins/sefi-core/scripts/ci/validate-no-personal-paths.sh"
expect_code 0 "the shipped scan ignores benchmarks/__pycache__/*.pyc and benchmarks/results/*" \
  bash "$NPT/plugins/sefi-core/scripts/ci/validate-no-personal-paths.sh"
# strip the two -not -path guards from the benchmarks find line -> the same tree now trips.
sed "s#find benchmarks -type f .*#find benchmarks -type f#" "$VNP" \
  > "$NPT/plugins/sefi-core/scripts/ci/no-exclude.sh"
expect_code 1 "without the benchmarks exclusions the identical tree is flagged (exit 1)" \
  bash "$NPT/plugins/sefi-core/scripts/ci/no-exclude.sh"
rm -rf "$NPT"

echo
echo "=== compress-output.sh (2026-08-11 audit: a failure could report zero diagnostics) ==="

CW="$(mktemp -d)"

# The bug: on failure the compressor printed only lines matching error|fail|exception. A
# tool that fails without naming one of those words produced a FAIL line, a log pointer,
# and nothing else -- leaving the qa-engineer re-running the gate with no diagnostic at all.
cmp_out="$( cd "$CW" && bash "$CORE/scripts/compress-output.sh" t \
  sh -c 'echo "2 tests did not pass"; echo "expected 3, got 4"; exit 1' 2>&1 )" || true
case "$cmp_out" in
  *"expected 3, got 4"*) ok "a failure with no error-keyword lines still shows the output tail" ;;
  *) bad "no diagnostics for a keyword-free failure: $cmp_out" ;;
esac

# The keyword path must not regress, dedup included.
cmp_out="$( cd "$CW" && bash "$CORE/scripts/compress-output.sh" t \
  sh -c 'echo "Error: boom"; echo "Error: boom"; exit 1' 2>&1 )" || true
case "$cmp_out" in
  *"2 Error: boom"*) ok "keyword lines are still deduped with a count" ;;
  *) bad "the dedup path regressed: $cmp_out" ;;
esac

# A failure with no output at all must say so rather than printing an empty section.
cmp_out="$( cd "$CW" && bash "$CORE/scripts/compress-output.sh" t sh -c 'exit 3' 2>&1 )" || true
case "$cmp_out" in
  *"produced no output"*) ok "a silent failure is labelled, not left blank" ;;
  *) bad "a silent failure printed nothing useful: $cmp_out" ;;
esac

# The wrapped command's exit code is still preserved (fail-open contract).
expect_code 3 "the wrapped command's exit code survives compression" \
  bash -c "cd '$CW' && bash '$CORE/scripts/compress-output.sh' t sh -c 'exit 3'"
rm -rf "$CW"

echo
echo "=== gen-router.sh (audit gap 5.1: trace notes evicting decisions) ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/memory/daily" "$TMP/memory/decisions"
printf -- '---\ntags: [index]\nmanaged-by: sefi-agents\n---\n# Memory Vault -- Router\n<!-- GENERATED:router -->\n<!-- /GENERATED:router -->\n' > "$TMP/memory/index.md"
printf -- '---\ntags: [daily]\nkeywords: alpha\n---\n' > "$TMP/memory/daily/2026-01-01.md"
printf -- '---\ntags: [decision]\nkeywords: zulu\n---\n' > "$TMP/memory/decisions/some-choice.md"

( cd "$TMP" && bash "$CORE/scripts/gen-router.sh" ) >/dev/null 2>&1

dec_line="$(grep -n 'decisions/some-choice' "$TMP/memory/index.md" | head -1 | cut -d: -f1)"
day_line="$(grep -n 'daily/2026-01-01' "$TMP/memory/index.md" | head -1 | cut -d: -f1)"
# Alphabetically "daily" sorts before "decisions", so a plain sort puts the trace note
# first and the injection's ~16-line window drops decisions entirely. Durability order
# must win over byte order.
if [ -n "$dec_line" ] && [ -n "$day_line" ] && [ "$dec_line" -lt "$day_line" ]; then
  ok "decisions/ precedes daily/ in the generated router"
else
  bad "decisions/ must precede daily/ (decisions at line ${dec_line:-none}, daily at line ${day_line:-none})"
fi

# The pre-existing drift check must not regress: a new note makes the router stale.
printf -- '---\ntags: [daily]\nkeywords: beta\n---\n' > "$TMP/memory/daily/2026-01-02.md"
expect_code 1 "--check flags drift after a new note is added" \
  bash -c "cd '$TMP' && bash '$CORE/scripts/gen-router.sh' --check"

echo
echo "=== inject-memory.sh (2026-08-11 audit: half the injection window spent on boilerplate) ==="

IW="$(mktemp -d)"
mkdir -p "$IW/memory/decisions" "$IW/memory/daily"
cp "$CORE/templates/memory/index.md" "$IW/memory/index.md"
printf -- '---\ntags: [decision]\nkeywords: auth\ndescription: use PKCE\n---\n' > "$IW/memory/decisions/auth.md"
printf -- '---\ntags: [daily]\nkeywords: note1\n---\n' > "$IW/memory/daily/2026-01-01.md"
( cd "$IW" && bash "$CORE/scripts/gen-router.sh" ) >/dev/null 2>&1

inj="$( cd "$IW" && bash "$CORE/scripts/inject-memory.sh" 2>/dev/null )"

# The router lines are the only part carrying signal; they must be present.
case "$inj" in
  *"decisions/auth"*) ok "the generated router block is injected" ;;
  *) bad "router lines missing from the injection: $inj" ;;
esac

# The static preamble must NOT be. `head -n 40` re-sent the frontmatter, title and folder
# list every session -- roughly half the 1500-char cap on boilerplate the model gains
# nothing from, while truncating the routing lines it does need.
case "$inj" in
  *"Entry point to the Obsidian-style memory vault"*|*"tags: [index]"*)
    bad "static preamble is still being injected (the head-40 window is back)" ;;
  *) ok "static index.md preamble is no longer injected" ;;
esac

# An initialized-but-empty vault says so in one line rather than injecting a page of
# folder headers describing an empty vault.
IE="$(mktemp -d)"
mkdir -p "$IE/memory"
cp "$CORE/templates/memory/index.md" "$IE/memory/index.md"
inj_empty="$( cd "$IE" && bash "$CORE/scripts/inject-memory.sh" 2>/dev/null )"
case "$inj_empty" in
  *"initialized but empty"*) ok "an empty vault injects a single-line notice" ;;
  *) bad "empty-vault case produced: $inj_empty" ;;
esac
rm -rf "$IE"

# A hand-written index.md with no markers must still inject something rather than nothing.
IH="$(mktemp -d)"
mkdir -p "$IH/memory"
printf '# my own router\n- see [[decisions/thing]]\n' > "$IH/memory/index.md"
inj_hand="$( cd "$IH" && bash "$CORE/scripts/inject-memory.sh" 2>/dev/null )"
case "$inj_hand" in
  *"decisions/thing"*) ok "a marker-less hand-written index still falls back to the head window" ;;
  *) bad "marker-less fallback produced: $inj_hand" ;;
esac
rm -rf "$IH"

# The hard char cap still binds.
IC="$(mktemp -d)"
mkdir -p "$IC/memory/decisions" "$IC/config"
cp "$CORE/templates/memory/index.md" "$IC/memory/index.md"
printf 'memory:\n  inject_char_cap: 120\n' > "$IC/config/sefi.config.yml"
i=0; while [ "$i" -lt 40 ]; do
  printf -- '---\ntags: [decision]\nkeywords: k%s\n---\n' "$i" > "$IC/memory/decisions/d$i.md"; i=$((i + 1))
done
( cd "$IC" && bash "$CORE/scripts/gen-router.sh" ) >/dev/null 2>&1
n_chars="$( cd "$IC" && bash "$CORE/scripts/inject-memory.sh" 2>/dev/null | wc -c | tr -d ' ')"
if [ "$n_chars" -le 121 ]; then
  ok "memory.inject_char_cap still bounds the injection ($n_chars bytes)"
else
  bad "injection exceeded the configured cap ($n_chars bytes for a cap of 120)"
fi
rm -rf "$IC" "$IW"

echo
echo "=== resolve-shared-memory-path.sh (cross-project memory mirror: fail-closed on any uncertainty) ==="

RSM="$(mktemp -d)"
mkdir -p "$RSM/config"
printf 'memory:\n  cross_project_enabled: true\n  cross_project_folder_name: sefi-memory\n' > "$RSM/config/sefi.config.yml"

# A known CI/cloud marker must skip the mirror outright: no output, nonzero exit. Real CI
# runners already set GITHUB_ACTIONS/CI themselves, so this assertion holds under the
# suite's own real environment with no extra stubbing needed.
out="$( cd "$RSM" && CI=true bash "$CORE/scripts/resolve-shared-memory-path.sh" 2>/dev/null )"
rc=0; ( cd "$RSM" && CI=true bash "$CORE/scripts/resolve-shared-memory-path.sh" >/dev/null 2>&1 ) || rc=$?
if [ -z "$out" ] && [ "$rc" -ne 0 ]; then
  ok "a CI-marker env var skips the mirror (no output, exit $rc)"
else
  bad "CI marker did not skip the mirror (output='$out' exit=$rc)"
fi

# cross_project_enabled: false must skip regardless of environment.
printf 'memory:\n  cross_project_enabled: false\n' > "$RSM/config/sefi.config.yml"
# cd into $RSM first so CONFIG resolves against the scratch dir like the sibling cases.
( cd "$RSM" && expect_code 1 "cross_project_enabled: false skips the mirror" \
  env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX bash "$CORE/scripts/resolve-shared-memory-path.sh" )
printf 'memory:\n  cross_project_enabled: true\n  cross_project_folder_name: sefi-memory\n' > "$RSM/config/sefi.config.yml"

# The positive path: stub systemd-detect-virt to report "none" (a real local machine) and
# strip every ephemeral env marker, since the suite's own CI runner is itself a container
# and would otherwise make this branch untestable. Two calls must agree -- idempotent
# resolution, not a path that drifts between invocations.
RVBIN="$(mktemp -d)"
printf '#!/bin/sh\necho none\n' > "$RVBIN/systemd-detect-virt"; chmod +x "$RVBIN/systemd-detect-virt"
mkdir -p "$RSM/fakehome"
p1="$( cd "$RSM" && env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$RVBIN:$PATH" HOME="$RSM/fakehome" bash "$CORE/scripts/resolve-shared-memory-path.sh" 2>/dev/null )"
p2="$( cd "$RSM" && env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$RVBIN:$PATH" HOME="$RSM/fakehome" bash "$CORE/scripts/resolve-shared-memory-path.sh" 2>/dev/null )"
if [ -n "$p1" ] && [ "$p1" = "$p2" ]; then
  ok "a non-ephemeral environment resolves a path, identically on a second call ($p1)"
else
  bad "resolution was not idempotent or empty (p1='$p1' p2='$p2')"
fi
rm -rf "$RVBIN"

# An unknown platform (uname reports something this script has no branch for) fails closed
# rather than guessing a path shape. Also stub systemd-detect-virt to "none" so this
# specifically exercises the unknown-OS branch, not the (also-passing) ephemeral check --
# the suite's own CI runner would otherwise satisfy exit 1 for the wrong reason.
UVBIN="$(mktemp -d)"
printf '#!/bin/sh\n[ "$1" = "-s" ] && echo PlanNine || echo unknown\n' > "$UVBIN/uname"; chmod +x "$UVBIN/uname"
printf '#!/bin/sh\necho none\n' > "$UVBIN/systemd-detect-virt"; chmod +x "$UVBIN/systemd-detect-virt"
expect_code 1 "an unrecognized OS fails closed rather than guessing a path" \
  env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$UVBIN:$PATH" bash "$CORE/scripts/resolve-shared-memory-path.sh"
rm -rf "$UVBIN"

rm -rf "$RSM"

echo
echo "=== write-shared-memory-mirror.sh (project-slug sanitization and harness fallback) ==="

WSM="$(mktemp -d)"
mkdir -p "$WSM/config" "$WSM/fakehome"
printf 'memory:\n  cross_project_enabled: true\n  cross_project_folder_name: sefi-memory\n' > "$WSM/config/sefi.config.yml"
printf 'quick test note\n' > "$WSM/note.md"
git -C "$WSM" init -q
git -C "$WSM" remote add origin "git@github.com:Some-Owner/My.Repo.git"

WVBIN="$(mktemp -d)"
printf '#!/bin/sh\necho none\n' > "$WVBIN/systemd-detect-virt"; chmod +x "$WVBIN/systemd-detect-virt"

# A remote URL with mixed case and punctuation must sanitize to a lowercase, path-safe
# slug -- no "/", no leftover ":" or ".git", so it can never be misread as a path
# separator or escape the project subfolder it names.
dest1="$( cd "$WSM" && env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$WVBIN:$PATH" HOME="$WSM/fakehome" bash "$CORE/scripts/write-shared-memory-mirror.sh" "My Topic" note.md 2>/dev/null )"
case "$dest1" in
  *"/github.com-some-owner-my.repo/"*) ok "git remote URL sanitizes to a lowercase, path-safe project slug" ;;
  *) bad "project-slug sanitization produced: $dest1" ;;
esac

# No .sefi/harness marker: falls back to the literal unknown-harness, never erroring.
case "$dest1" in
  *"/unknown-harness-"*) ok "a missing .sefi/harness marker falls back to unknown-harness" ;;
  *) bad "harness fallback produced: $dest1" ;;
esac

# With a real marker present, the mirror filename carries it instead of the fallback.
mkdir -p "$WSM/.sefi"; echo claude > "$WSM/.sefi/harness"
dest2="$( cd "$WSM" && env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$WVBIN:$PATH" HOME="$WSM/fakehome" bash "$CORE/scripts/write-shared-memory-mirror.sh" "My Topic" note.md 2>/dev/null )"
case "$dest2" in
  *"/claude-"*) ok "a present .sefi/harness marker names the mirror file" ;;
  *) bad "harness marker was not picked up: $dest2" ;;
esac

rm -rf "$WSM" "$WVBIN"

echo
echo "=== hook script executable bit (inject-memory.sh shipped as 100644, breaking a fresh symlink-mode SessionStart) ==="

# hooks.json invokes its "command" scripts directly -- no "bash"/"sh" interpreter prefix --
# so Claude Code execs the path itself, which requires the executable bit on POSIX. Every
# script referenced that way must be tracked in git as 100755, or a fresh clone/install
# ships a SessionStart (or PreToolUse) hook that fails with "Permission denied" the moment
# it fires. check-bash-write.sh already carried the bit; inject-memory.sh did not -- the
# test suite's own invocations always went through an explicit `bash inject-memory.sh`,
# which masks exactly this failure mode. Assert against the tracked git mode, not just the
# working-tree file, since the tracked mode is what a fresh clone actually ships.
HOOKS_JSON="$CORE/hooks/hooks.json"
if command -v jq >/dev/null 2>&1 && [ -f "$HOOKS_JSON" ]; then
  hook_cmds="$(jq -r '.. | .command? // empty' "$HOOKS_JSON")"
  if [ -z "$hook_cmds" ]; then
    bad "hooks.json yielded no .command entries to check (parser or fixture broke)"
  fi
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # CRLF checkouts make jq echo a trailing carriage return, which would defeat the quote stripping below.
    cmd="${cmd%$'\r'}"
    # v0.3.20 quote-wrapped every command (Windows path-with-space fix), so strip a
    # surrounding literal `"..."` before matching the placeholder prefix -- otherwise the
    # leading quote character makes every entry look untracked.
    cmd="${cmd#\"}"; cmd="${cmd%\"}"
    rel="plugins/sefi-core/${cmd#\$\{CLAUDE_PLUGIN_ROOT\}/}"
    mode="$(cd "$ROOT" && git ls-files -s "$rel" 2>/dev/null | awk '{print $1}')"
    case "$mode" in
      100755) ok "$rel is tracked executable (100755), matching how hooks.json invokes it" ;;
      "") bad "$rel referenced by hooks.json is not tracked in git at all" ;;
      *) bad "$rel is tracked as $mode, not 100755 -- hooks.json execs it with no interpreter prefix, so it will fail with Permission denied" ;;
    esac
  done <<< "$hook_cmds"
else
  echo "  SKIP: hook script executable-bit check (jq not installed)"
fi

echo
echo "=== loop move detection (2026-08-11 audit: prose satisfied the five-move gate) ==="

# validate-loops.sh and loop-readiness.sh both detected the five moves with a bare
# `grep -q Discovery`, so a spec that merely used the words in a sentence -- with no
# section for any move -- scored as a complete loop. loop-readiness.sh is the testable one
# (it reads loops/ relative to cwd); both now use the same `^## <Move>` anchor.
LR="$(mktemp -d)"
mkdir -p "$LR/loops"
cat > "$LR/loops/prose.loop.md" <<'PROSE'
# Loop: prose
managed-by: sefi-agents
agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

This loop does Discovery and Handoff, then Verification and Persistence, all
scheduled via SCHEDULING. It has a human checkpoint too.
## Budget
per-run cap: $0.50
PROSE
lr_out="$( cd "$LR" && bash "$CORE/scripts/loop-readiness.sh" 2>/dev/null )"
lr_score="${lr_out##*: }"; lr_score="${lr_score%%/*}"
if [ "${lr_score:-100}" -le 40 ]; then
  ok "a prose-only spec no longer scores the five-move signal ($lr_out)"
else
  bad "prose-only spec still scores the move signal: $lr_out"
fi

# A spec with real headings must still score them.
cat > "$LR/loops/real.loop.md" <<'REAL'
# Loop: real
managed-by: sefi-agents
agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out
## Trigger (SCHEDULING)
cloud: cron
## Discovery
skill: loop-engineering
## Handoff
one worktree per finding
## Verification
generator/evaluator split
## Persistence
state file: `state/real.md`
## Budget
per-run cap: $0.50   daily cap: $2.00
## Human checkpoint
PRs are opened, never merged.
REAL
lr_out="$( cd "$LR" && bash "$CORE/scripts/loop-readiness.sh" 2>/dev/null | grep '^real:' )"
case "$lr_out" in
  *"60/100"*|*"80/100"*|*"100/100"*) ok "a properly sectioned spec still scores its moves ($lr_out)" ;;
  *) bad "a valid spec lost its move score: $lr_out" ;;
esac
rm -rf "$LR"

echo
echo "=== probe-tools.sh (README claimed a probe that did not exist until 2026-08-11) ==="

PB="$CORE/scripts/probe-tools.sh"

# MISSING: the failure this repo actually hit. state/triage.md, first live cycle: two of six
# findings lost to "gh CLI not installed ... unreachable this cycle", discovered mid-cycle.
expect_code 1 "a missing tool fails the probe" bash "$PB" --quiet definitely-not-a-real-binary-xyz

# BROKEN: the shape `command -v` cannot see -- installed and unusable, which is what the
# predecessor's browser tool was when it ate a 50-iteration retry budget.
PBIN="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$PBIN/jq"; chmod +x "$PBIN/jq"
expect_code 1 "an installed-but-broken tool fails the probe (presence is not health)" \
  env PATH="$PBIN:$PATH" bash "$PB" --quiet jq
rm -rf "$PBIN"

# A working tool passes.
expect_code 0 "a working tool passes the probe" bash "$PB" --quiet git

# --loop reads the spec's own requires-tools declaration.
PL="$(mktemp -d)"
printf 'requires-tools: git\n' > "$PL/good.loop.md"
expect_code 0 "--loop probes the spec's requires-tools line" bash "$PB" --quiet --loop "$PL/good.loop.md"
printf 'requires-tools: definitely-not-a-real-binary-xyz\n' > "$PL/bad.loop.md"
expect_code 1 "--loop fails when a declared tool is unusable" bash "$PB" --quiet --loop "$PL/bad.loop.md"

# `none` is a deliberate declaration, not an empty value to fall through on.
printf 'requires-tools: none\n' > "$PL/none.loop.md"
expect_code 0 "requires-tools: none is a valid declaration" bash "$PB" --quiet --loop "$PL/none.loop.md"

# A spec with no declaration at all is a usage error, never a silent pass.
printf '# Loop: x\n' > "$PL/undeclared.loop.md"
expect_code 2 "a spec with no requires-tools line is a usage error, not a pass" \
  bash "$PB" --quiet --loop "$PL/undeclared.loop.md"
rm -rf "$PL"

# Every shipped loop spec must declare the line (validate-loops.sh enforces it; this
# asserts the shipped templates actually satisfy their own gate).
for lf in "$CORE"/templates/loops/*.loop.md; do
  [ -e "$lf" ] || continue
  if grep -qE '^requires-tools:[[:space:]]*[^[:space:]]' "$lf"; then
    ok "$(basename "$lf") declares requires-tools"
  else
    bad "$(basename "$lf") is missing its requires-tools line"
  fi
done

echo
echo "=== check-handoff.sh (the handoff rule was prose-only until 2026-08-11) ==="

CH="$CORE/scripts/check-handoff.sh"
good_env='agent: software-engineer
reads: state/plan-auth.md
writes: /abs/proj/.worktrees/feat-auth
budget: dispatch
context: Implement slice 2. The API contract is POST /session returning 201 with a session id.'

expect_code 0 "a well-formed envelope passes" bash -c "printf '%s\n' '$good_env' | bash '$CH' -"

# The live failure recorded in qa-engineer.md item 4: a dispatch with no pinned ABSOLUTE
# output path wrote to the user's home directory, and the reviewer reading the designated
# folder approved an empty one. An empty folder and never-written work look identical.
rel_env="${good_env/\/abs\/proj\/.worktrees\/feat-auth/.worktrees/feat-auth}"
expect_code 1 "a relative writes: path blocks the dispatch" \
  bash -c "printf '%s\n' '$rel_env' | bash '$CH' -"

# The handoff rule's other half: the receiving agent does not share the dispatcher's
# context window, so a back-reference resolves to nothing on its side.
back_env="${good_env/Implement slice 2./Implement the slice as discussed above.}"
expect_code 1 "a dangling back-reference blocks the dispatch" \
  bash -c "printf '%s\n' '$back_env' | bash '$CH' -"

# A typo'd agent slug routes nowhere and would otherwise surface as a mysterious no-op.
bad_agent="${good_env/software-engineer/backend-guy}"
expect_code 1 "an agent slug resolving to no file blocks the dispatch" \
  bash -c "printf '%s\n' '$bad_agent' | bash '$CH' -"

expect_code 1 "an envelope missing required fields blocks the dispatch" \
  bash -c "printf 'agent: qa-engineer\n' | bash '$CH' -"

echo
echo "=== check-bar.sh (bar-comparison: Named / Fetchable / Comparable, gated before a qa-engineer verdict may cite it) ==="

CB="$CORE/scripts/check-bar.sh"
BAR_SOURCE="$(mktemp)"

expect_code 0 "a named bar with a resolvable local source passes" \
  bash -c "printf 'bar: Linear issue list view\nsource: %s\ncompare: keyboard-first triage speed\n' '$BAR_SOURCE' | bash '$CB' -"

expect_code 1 "'award-winning SaaS sites' is rejected as a category" \
  bash -c "printf 'bar: award-winning SaaS sites\nsource: %s\ncompare: layout density\n' '$BAR_SOURCE' | bash '$CB' -"

expect_code 1 "a source pointing at a nonexistent path is rejected" \
  bash -c "printf 'bar: Linear issue list view\nsource: %s.does-not-exist\ncompare: layout density\n' '$BAR_SOURCE' | bash '$CB' -"

expect_code 1 "an empty compare: is rejected" \
  bash -c "printf 'bar: Linear issue list view\nsource: %s\ncompare: \n' '$BAR_SOURCE' | bash '$CB' -"

rm -f "$BAR_SOURCE"

echo
echo "=== check-reply.sh (live 2026-08-17: prompt-engineer returned a full HTML document against 'exactly this digest and nothing else') ==="

CR="$CORE/scripts/check-reply.sh"
AG="$CORE/agents"
RTMP="$(mktemp -d)"
BUDGET_ARG="--config $BUDGET_TPL"

# The shape a valid prompt-engineer reply takes -- all three declared labels, nothing else.
cat > "$RTMP/good.txt" <<'EOF'
INTENTS: Create an HTML file in the root folder describing what is known about the user.
CONSTRAINTS: minimalist; black and white; contrast compliance; HTML file is the only deliverable.
SUGGESTED: "design / UI / UX spec" then "build / implement slice".
EOF
expect_code 0 "a well-formed prompt-engineer digest passes" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/good.txt"

# The actual observed failure: the digest, plus a deliverable owned by two other agents.
# The tool whitelist held here (no file was written) -- only content leaked, which is
# precisely the gap this gate closes.
cp "$RTMP/good.txt" "$RTMP/leak.txt"
printf '<!DOCTYPE html>\n<html lang="en"><body><h1>About</h1></body></html>\n' >> "$RTMP/leak.txt"
expect_code 1 "a digest plus a full HTML document is rejected (the live failure)" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/leak.txt"

# Verbosity bound: per_agent_return_tokens had sat in budget.yml since v0.2.1 with no
# script reading it.
{ cat "$RTMP/good.txt"; for _ in $(seq 1 200); do printf 'padding '; done; } > "$RTMP/long.txt"
expect_code 1 "an over-budget reply is rejected against per_agent_return_tokens" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/long.txt"

# Cap raised 150 -> 200 (2026-08-18): live data showed qa-engineer's verdict-with-evidence
# replies landing at 162 and 172 words against the old cap -- not rambling, just the natural
# size of a PASS/REJECT call that has to cite file:line evidence. A reply in that real,
# previously-punished range must now pass (all labels present, same as good.txt, so a failure
# here can only be the word-count check); a reply that is actually bloated must still fail.
{ cat "$RTMP/good.txt"; for _ in $(seq 1 131); do printf 'word '; done; } > "$RTMP/onceoverold.txt"
expect_code 0 "a 172-word reply (the real qa-engineer incident) passes against the 200 cap" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/onceoverold.txt"
{ cat "$RTMP/good.txt"; for _ in $(seq 1 179); do printf 'word '; done; } > "$RTMP/stilltoolong.txt"
expect_code 1 "a 220-word reply is still rejected -- the raise did not remove the ceiling" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/stilltoolong.txt"

# per_agent_return_tokens_target (150, soft): "aim for 150, 200 only if not possible" --
# the 172-word reply passes (above) AND must carry a visible, non-blocking NOTE that it
# missed the target, so the signal to write shorter next time is not silently dropped just
# because it did not fail. A reply well under target must carry no such NOTE (no false
# advisory on a reply that is already fine). Captured into a variable rather than piped
# live into `grep -q`: `grep -q` exits the instant it matches without draining its input,
# and under this file's own `set -o pipefail`, the writer can get SIGPIPE (exit 141) for
# writing past a closed pipe -- clobbering the reported status even when the match was
# real. Same `case` idiom the gate.sh checks above already use for exactly this reason.
target_note_over="$(bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/onceoverold.txt" 2>&1 >/dev/null)"
case "$target_note_over" in
  *"NOTE:"*"over the 150-word target"*) ok "a 172-word reply still gets a non-blocking NOTE that it missed the 150-word target" ;;
  *) bad "a 172-word reply did not get the target-missed advisory NOTE" ;;
esac
target_note_under="$(bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/good.txt" 2>&1 >/dev/null)"
case "$target_note_under" in
  *"NOTE:"*"target"*) bad "a well-under-target reply wrongly got the target-missed advisory NOTE" ;;
  *) ok "a well-under-target reply gets no target advisory (only a real miss should note)" ;;
esac

grep -v '^SUGGESTED:' "$RTMP/good.txt" > "$RTMP/missing.txt"
expect_code 1 "a reply omitting a declared label is rejected" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/missing.txt"

# Guards against a gate that only accepts one agent's shape. qa-engineer's contract names
# "If REJECT:" and "If PASS:" as conditional branches mid-line; requiring those as labels
# would fail every valid verdict, so only start-of-line labels count.
printf 'VERDICT: PASS\nExecuted npm test -- 14 passing, before/after in .worktrees/logs/.\n' > "$RTMP/qa.txt"
expect_code 0 "a qa-engineer VERDICT reply passes (conditional branches are not labels)" \
  bash "$CR" $BUDGET_ARG "$AG/qa-engineer.md" "$RTMP/qa.txt"

# A table-shaped contract must report CANNOT-CHECK, never a false rejection: a gate that
# cries wolf on valid replies trains its caller to ignore it.
printf 'item | class | evidence | routed-to | urgency\nCI red | actionable | run 412 | devops-engineer | routine\n' > "$RTMP/support.txt"
expect_code 3 "support-engineer's table-shaped contract exits 3 CANNOT-CHECK, not a false 1" \
  bash "$CR" $BUDGET_ARG "$AG/support-engineer.md" "$RTMP/support.txt"

# A second live gap found by hunting further (2026-08-17): an unanchored label match let a
# mid-sentence mention of a label word pass as if it were a real section.
printf 'INTENTS: build a page.\nCONSTRAINTS: none stated.\nI could not form a SUGGESTED: route because the request was ambiguous.\n' > "$RTMP/prose_label.txt"
expect_code 1 "a label merely MENTIONED in prose (not a real section) is rejected" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/prose_label.txt"

# A third: a single accurate verbatim quote of one plan heading must not be mistaken for a
# leaked plan -- only correlated presence of several headings is real evidence.
cat > "$RTMP/quote_one_heading.txt" <<'EOF'
INTENTS: build the feature described in the attached plan.
CONSTRAINTS: the message verbatim-quotes an existing plan section: "## Done Criteria
`npm test` passes and the endpoint returns 201."
SUGGESTED: "build / implement slice" (software-engineer).
EOF
expect_code 0 "quoting ONE plan heading verbatim is not a leaked plan" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/quote_one_heading.txt"

# A genuinely leaked plan (multiple correlated headings) must still be caught.
cat > "$RTMP/leaked_plan.txt" <<'EOF'
INTENTS: build the feature.
CONSTRAINTS: none stated.
SUGGESTED: "build / implement slice" (software-engineer).
## Objective
Add the feature.
## Steps
- [ ] 1. do it (needs: -)
## Done Criteria
tests pass
EOF
expect_code 1 "a reply carrying 3+ correlated plan headings is still rejected as a leaked plan" \
  bash "$CR" $BUDGET_ARG "$AG/prompt-engineer.md" "$RTMP/leaked_plan.txt"

rm -rf "$RTMP"

echo
echo "=== memory producer (2026-08-11 audit: the vault had a consumer and no producer) ==="

# knowledge-manager.md read memory/daily/*.md as "the raw material" and distilled it weekly;
# every other agent filed observations as "a candidate for the knowledge-manager"; and NO
# agent, hook or command ever wrote a daily note. /sefi:init created memory/daily/ and it
# stayed empty forever, so the weekly distill was a permanent no-op and SessionStart had
# nothing to inject. These assert the producer exists and stays wired.
if grep -rlq 'memory/daily' "$CORE/agents"; then
  producer="$(grep -rl 'memory/daily' "$CORE/agents" | head -1)"
  if grep -qiE 'author|append|write' "$producer"; then
    ok "an agent authors daily notes ($(basename "$producer"))"
  else
    bad "$(basename "$producer") names memory/daily but never writes to it"
  fi
else
  bad "no agent references memory/daily -- the vault has no producer"
fi

# close_out was declared in every loop spec and defined nowhere; goal_intake had a
# reference file and it did not. An undefined signal is a label, not a gate.
if [ -f "$CORE/skills/sefi-orchestration/references/close-out.md" ]; then
  ok "close_out has a defined behavior reference"
else
  bad "close_out is declared in loop specs but has no behavior reference"
fi

# Every loop must actually invoke the producer, not merely list the signal in its header.
for lf in "$CORE"/templates/loops/*.loop.md; do
  [ -e "$lf" ] || continue
  if grep -q 'close_out: dispatch the knowledge-manager' "$lf"; then
    ok "$(basename "$lf") invokes the close_out dispatch"
  else
    bad "$(basename "$lf") declares close_out but never dispatches it"
  fi
done

# The privacy filter is why this is an agent dispatch and not a Stop hook. If a hook ever
# starts writing the vault, that filter is bypassed.
if grep -q 'SessionStart' "$CORE/hooks/hooks.json" && ! grep -qE '"(Stop|SessionEnd|PostToolUse)"' "$CORE/hooks/hooks.json"; then
  ok "no hook writes the vault (the privacy filter stays on the write path)"
else
  bad "hooks.json declares a write-side hook -- the memory-protocol privacy filter cannot run in one"
fi

echo
echo "=== plan structure (2026-08-11: the plan is consumed by 3 agents, 2 were guessing) ==="

PV="$(mktemp -d)"; mkdir -p "$PV/state"

# The product-manager's worked example must pass the product-manager's own gate. An agent
# that teaches a format its validator rejects trains every plan into a failure -- and a
# small model matches structure from the example far more than from the prose.
extract_plan_example() {
  # extract_plan_example <dest-dir> -- write <dest-dir>/state/plan-example.md from
  # product-manager.md's worked example, using the first WORKING python (python3,
  # then python, then py). `command -v` alone cannot tell the Microsoft Store
  # python3 alias stub from a real interpreter; each candidate is smoke-tested.
  # Returns 0 when the file was written.
  local dest="$1" py=""
  for t in python3 python py; do
    if command -v "$t" >/dev/null 2>&1 && "$t" -c 'import json,sys' >/dev/null 2>&1; then
      py="$t"; break
    fi
  done
  [ -n "$py" ] || return 1
  ( cd "$ROOT" && "$py" - "$dest" <<'EXTRACT' 2>/dev/null
import sys, pathlib, re
t = pathlib.Path("plugins/sefi-core/agents/product-manager.md").read_text()
m = re.search(r'## Worked example.*?```markdown\n(.*?)```', t, re.S)
if m:
    pathlib.Path(sys.argv[1] + "/state/plan-example.md").write_text(m.group(1))
EXTRACT
  )
}

extract_plan_example "$PV"

if [ -f "$PV/state/plan-example.md" ]; then
  if ( cd "$PV" && bash "$CORE/scripts/validate-plan-structure.sh" ) 2>/dev/null; then
    ok "the product-manager's worked example passes validate-plan-structure.sh"
  else
    bad "the product-manager teaches a plan format its own gate rejects"
  fi

  # Every step needs a dependency marker: the engineering-manager sequences from these, and
  # a flat checkbox list left max_parallel_worktrees unusable without guessing.
  sed 's/ (needs: 1)//' "$PV/state/plan-example.md" > "$PV/state/plan-nodeps.md"
  rm -f "$PV/state/plan-example.md"
  if ( cd "$PV" && bash "$CORE/scripts/validate-plan-structure.sh" ) 2>/dev/null; then
    bad "a step with no (needs: ...) marker was accepted"
  else
    ok "a step missing its (needs: ...) marker is rejected"
  fi
  rm -f "$PV/state/plan-nodeps.md"

  # `none` is a deliberate declaration; blank is an omission. The probe needs the difference.
  printf '## Objective\nx\n## Steps\n- [ ] 1. do a thing (needs: -)\n## Files Touched\na.sh\n## Requires Tools\n\n## Risks\nnone\n## Done Criteria\nit runs\n' > "$PV/state/plan-blank.md"
  if ( cd "$PV" && bash "$CORE/scripts/validate-plan-structure.sh" ) 2>/dev/null; then
    bad "an empty '## Requires Tools' was accepted"
  else
    ok "an empty '## Requires Tools' is rejected (use 'none' deliberately)"
  fi
else
  bad "could not extract the worked example from product-manager.md"
fi
rm -rf "$PV"

echo
echo "=== install-opencode.sh (flexible-model mode, v0.3.18: OpenCode Zen's free catalog rotates -- deepseek-v4-flash-free was verified real 2026-08-11, retired by 2026-08-21) ==="

# The shipped default map now resolves opencode's high/mid/low to the literal sentinel
# "flexible", not a concrete model id -- hardcoding whatever is free on Zen this week
# breaks again the next time the free lineup turns over, which just happened. With
# "flexible", install-opencode.sh must write NO model: line and NO options: block at all,
# so every converted agent falls back to whatever model the human has actually configured
# in OpenCode itself (adapters/OPENCODE.md section 1) -- functional regardless of which
# model Zen is giving away for free on any given day.
TMP_OC="$(mktemp -d)"
OPENCODE_HOME="$TMP_OC" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1

oc_model="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC/agents/software-engineer.md" 2>/dev/null | head -1)"
case "$oc_model" in
  opus|sonnet|haiku)
    bad "a bare Claude Code alias ('$oc_model') survived into the OpenCode agent file" ;;
  "")
    ok "shipped default map ('flexible') writes no model: line -- the human's own OpenCode model selection governs" ;;
  *)
    bad "install-opencode.sh emitted a hardcoded model ('$oc_model') from the shipped default map -- exactly the fragility that broke when deepseek-v4-flash-free was retired" ;;
esac

if grep -q '^options:' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  bad "install-opencode.sh wrote an options: block from the shipped 'flexible' default map"
else
  ok "no options.reasoningEffort written for the shipped 'flexible' default map either"
fi

# The tier is this repo's own field and must not leak into a harness file.
if grep -q '^tier:' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  bad "tier: leaked into the converted OpenCode agent file"
else
  ok "install-opencode.sh consumes tier: without leaking it"
fi

# The mechanism must still work when a real map (a user override, or Zen offering a
# non-free model later) supplies concrete values: distinct per-tier models must survive,
# and must carry their own provider/model-id prefix or OpenCode dispatch fails hard --
# live-observed 2026-08-07, the same failure class as a bare Claude Code alias.
OC_MAP="$(mktemp)"
printf 'opencode:\n  high: opencode/judge-model\n  mid: opencode/build-model\n  low: opencode/cheap-model\n' > "$OC_MAP"
TMP_OC2="$(mktemp -d)"
OPENCODE_HOME="$TMP_OC2" bash "$CORE/scripts/install-opencode.sh" --model-map "$OC_MAP" >/dev/null 2>&1
qa_m="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC2/agents/qa-engineer.md" 2>/dev/null | head -1)"
se_m="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC2/agents/software-engineer.md" 2>/dev/null | head -1)"
if [ "$qa_m" = "opencode/judge-model" ] && [ "$se_m" = "opencode/build-model" ]; then
  ok "tiers still differentiate on OpenCode when a real map supplies models (qa=$qa_m vs engineer=$se_m), restoring generator/evaluator separation"
else
  bad "tier differentiation broken on OpenCode with a real map (qa='$qa_m' engineer='$se_m')"
fi
case "$qa_m" in
  */*) ok "a real OpenCode model ('$qa_m') carries a provider/model-id prefix" ;;
  "") bad "install-opencode.sh emitted no model: for a map that supplied a real value" ;;
  *) bad "OpenCode model '$qa_m' has no provider prefix -- dispatch will fail to resolve it" ;;
esac
rm -rf "$TMP_OC2" "$OC_MAP"
# Everything else must still survive byte-for-byte: pick one field per source line kind.
if grep -q '^disallowedTools: WebFetch, WebSearch$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null \
   && grep -q '^  edit: allow$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  ok "install-opencode.sh still converts tools/permission and keeps other fields intact"
else
  bad "install-opencode.sh regressed the tools/permission conversion or another frontmatter field"
fi

# Live-observed (2026-08-18): with no mode: field OpenCode defaults every agent to
# mode: all, putting all 13 specialists in the same Tab-cycle switcher as
# engineering-manager -- the exact direct-invocation path that caused the
# prompt-engineer scope-creep bug. Exactly one agent may be mode: primary.
primary_n="$(grep -l '^mode: primary$' "$TMP_OC"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
primary_file="$(grep -l '^mode: primary$' "$TMP_OC"/agents/*.md 2>/dev/null | xargs -n1 basename)"
subagent_n="$(grep -l '^mode: subagent$' "$TMP_OC"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "$primary_n" = "1" ] && [ "$primary_file" = "sefi-agents.md" ] && [ "$subagent_n" = "12" ]; then
  ok "exactly engineering-manager is mode: primary; the other 12 are mode: subagent"
else
  bad "mode: split is wrong (primary_n=$primary_n primary_file='$primary_file' subagent_n=$subagent_n)"
fi

# Live-confirmed (2026-08-18): an engineering-manager session used Bash-invoked sed -i to
# write state-file content despite disallowedTools: Write, Edit, MultiEdit -- OpenCode's
# flat bash: allow has the identical gap. An agent that fully disallows all three now gets a
# pattern-map deny list instead; an agent with real Write access (software-engineer,
# knowledge-manager -- only MultiEdit denied) must NOT be narrowed by this.
if grep -q '^  bash:$' "$TMP_OC/agents/sefi-agents.md" 2>/dev/null \
   && grep -qF '"sed -i*": deny' "$TMP_OC/agents/sefi-agents.md" 2>/dev/null \
   && grep -qF '"*": allow' "$TMP_OC/agents/sefi-agents.md" 2>/dev/null; then
  ok "sefi-agents's OpenCode bash: permission is a deny-pattern map, not a flat allow"
else
  bad "sefi-agents's OpenCode bash: permission did not get the write-pattern deny map"
fi
if grep -q '^  bash: allow$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  ok "software-engineer's OpenCode bash: stays a flat allow (real Write access, not narrowed)"
else
  bad "software-engineer's OpenCode bash: was unexpectedly narrowed despite real Write access"
fi
if grep -q '^  bash: allow$' "$TMP_OC/agents/knowledge-manager.md" 2>/dev/null; then
  ok "knowledge-manager's OpenCode bash: stays a flat allow (only MultiEdit denied, not Write)"
else
  bad "knowledge-manager's OpenCode bash: was unexpectedly narrowed (only MultiEdit is denied, not Write)"
fi

rm -rf "$TMP_OC"

echo
echo "=== ready-steps.sh (fan-out: the ready set from a plan's (needs: ...) markers, previously reasoned about in prose) ==="

RS="$CORE/scripts/ready-steps.sh"
PLANTMP="$(mktemp -d)"

cat > "$PLANTMP/linear.md" <<'EOF'
## Steps
- [ ] 1. first (needs: -)
- [ ] 2. second (needs: 1)
EOF
out="$(bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/linear.md" 2>/dev/null)"
[ "$out" = "1" ] && ok "a linear plan yields exactly step 1" || bad "linear plan ready set was '$out', wanted '1'"

sed -i.bak 's/\[ \] 1\./[x] 1./' "$PLANTMP/linear.md" && rm -f "$PLANTMP/linear.md.bak"
out="$(bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/linear.md" 2>/dev/null)"
[ "$out" = "2" ] && ok "checking step 1 releases step 2" || bad "after checking step 1, ready set was '$out', wanted '2'"

cat > "$PLANTMP/three.md" <<'EOF'
## Steps
- [ ] 1. a (needs: -)
- [ ] 2. b (needs: -)
- [ ] 3. c (needs: -)
EOF
out="$(bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/three.md" 2>/dev/null | tr '\n' ',')"
[ "$out" = "1,2,3," ] && ok "three (needs: -) steps yield three" || bad "three independent steps gave '$out', wanted '1,2,3,'"

cat > "$PLANTMP/four.md" <<'EOF'
## Steps
- [ ] 1. a (needs: -)
- [ ] 2. b (needs: -)
- [ ] 3. c (needs: -)
- [ ] 4. d (needs: -)
EOF
n="$(bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/four.md" 2>/dev/null | grep -c .)"
[ "$n" = "3" ] && ok "four independent steps cap at three (max_parallel_worktrees)" || bad "four independent steps emitted $n, wanted 3"

cat > "$PLANTMP/complete.md" <<'EOF'
## Steps
- [x] 1. a (needs: -)
- [x] 2. b (needs: 1)
EOF
expect_code 4 "all-checked plan exits 4 (COMPLETE)" bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/complete.md"

cat > "$PLANTMP/cycle.md" <<'EOF'
## Steps
- [ ] 1. a (needs: 2)
- [ ] 2. b (needs: 1)
EOF
expect_code 3 "a two-step cycle exits 3 (BLOCKED)" bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/cycle.md"

cat > "$PLANTMP/baddep.md" <<'EOF'
## Steps
- [ ] 1. a (needs: 9)
EOF
expect_code 1 "a dep on a nonexistent step exits 1 (malformed)" bash "$RS" --config "$BUDGET_TPL" "$PLANTMP/baddep.md"

rm -rf "$PLANTMP"

echo
echo "=== templates/hooks/pre-push (2026-08-18: human-checkpoint.md's never-auto-merge rule had zero deterministic enforcement) ==="

PP="$CORE/templates/hooks/pre-push"
expect_code 0 "a push to a feature branch is allowed" \
  bash -c "printf 'refs/heads/feat/x abc123 refs/heads/feat/x def456\n' | sh '$PP'"
expect_code 1 "a direct push to main is refused" \
  bash -c "printf 'refs/heads/main abc123 refs/heads/main def456\n' | sh '$PP'"
expect_code 1 "a direct push to master is refused" \
  bash -c "printf 'refs/heads/master abc123 refs/heads/master def456\n' | sh '$PP'"
expect_code 0 "a deliberate human override (SEFI_ALLOW_MAIN_PUSH=1) is allowed" \
  bash -c "printf 'refs/heads/main abc123 refs/heads/main def456\n' | SEFI_ALLOW_MAIN_PUSH=1 sh '$PP'"
expect_code 1 "a multi-ref push where only one ref is main is still refused" \
  bash -c "printf 'refs/heads/feat/x abc123 refs/heads/feat/x def456\nrefs/heads/main aaa111 refs/heads/main bbb222\n' | sh '$PP'"

echo
echo "=== check-bash-write.sh (2026-08-18: disallowedTools: Write,Edit,MultiEdit does not survive Bash -- live-confirmed via engineering-manager's own forensic self-audit, Bash-invoked Add-Content/sed -i wrote state-file content 8 times despite that line) ==="

CBW="$CORE/scripts/check-bash-write.sh"
export CLAUDE_PLUGIN_ROOT="$CORE"

bw_json() {
  # bw_json <agent_type> <command> -- minimal PreToolUse-shaped JSON for check-bash-write.sh.
  printf '{"agent_type":"%s","tool_input":{"command":"%s"}}' "$1" "$2"
}

expect_bw() {
  # expect_bw <expected-exit> <label> <agent_type> <command>
  local want="$1" label="$2" agent="$3" cmd="$4" got=0
  bw_json "$agent" "$cmd" | bash "$CBW" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then ok "$label (exit $got)"; else bad "$label (expected exit $want, got $got)"; fi
}

expect_bw 2 "sefi-agents: sed -i on a state file is blocked" \
  sefi-agents "sed -i s/a/b/ state/foo.md"
expect_bw 2 "qa-engineer: tee into a state file is blocked" \
  qa-engineer "echo hi | tee state/foo.md"
expect_bw 0 "sefi-agents: an ordinary grep is allowed" \
  sefi-agents "grep -rn TODO plugins/"
expect_bw 0 "software-engineer: sed -i is allowed (real Write access -- not this hook's concern)" \
  software-engineer "sed -i s/a/b/ src/foo.py"
expect_bw 0 "knowledge-manager: sed -i is allowed (only MultiEdit denied, not Write)" \
  knowledge-manager "sed -i s/a/b/ memory/foo.md"

got=0
printf '{"tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' | bash "$CBW" >/dev/null 2>&1 || got=$?
if [ "$got" -eq 0 ]; then ok "no agent_type: fails open (exit 0, nothing to scope enforcement to)"; else bad "no agent_type: expected exit 0, got $got"; fi

# The health-check fix (2026-08-18): `command -v python3` is presence-only, and this
# host's python3 is the Microsoft Store alias stub -- present, prints "Python was
# not found", exits 1 -- so the extractors returned empty and the gate failed OPEN
# (sed -i/tee exited 0, not 2; CI reddened 3 failed / 89 passed). Three cases pin
# the fix and its boundary, deterministically, on any host with bash + coreutils.
PYSHIM="$(mktemp -d)"
real_py=""
for t in python3 python py; do
  if command -v "$t" >/dev/null 2>&1 && "$t" -c 'import json,sys' >/dev/null 2>&1; then
    real_py="$(command -v "$t")"; break
  fi
done
mkpy() {
  # mkpy <name> <body> -- write a shim executable into PYSHIM.
  printf '#!/bin/sh\n%s\n' "$2" > "$PYSHIM/$1"
  chmod +x "$PYSHIM/$1"
}
mkpy jq 'exit 1'
mkpy python3 'exit 1'
if [ -n "$real_py" ]; then
  mkpy python "exec \"$real_py\" \"\$@\""
fi

# (a) broken python3 + working python -> the gate still blocks sed -i (exit 2).
got=0
printf '{"agent_type":"sefi-agents","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' \
  | env PATH="$PYSHIM:$PATH" bash "$CBW" >/dev/null 2>&1 || got=$?
if [ "$got" -eq 2 ]; then
  ok "broken python3 + working python: sed -i still blocked (exit 2)"
else
  bad "broken python3 + working python: sed -i expected exit 2, got $got"
fi

# (b) broken python3 + working python -> the worked-example extraction still
# succeeds (the CI-red "could not extract the worked example" failure).
EXB="$(mktemp -d)"; mkdir -p "$EXB/state"
if PATH="$PYSHIM:$PATH" extract_plan_example "$EXB" && [ -f "$EXB/state/plan-example.md" ]; then
  ok "worked-example extraction survives a broken python3 (working python fallback)"
else
  bad "worked-example extraction failed under a broken python3 shim"
fi
rm -rf "$EXB"

# (c) no working parser at all (jq, python3, python, py all broken) -> the
# documented fail-open exit 0 is preserved, not silently regressed.
mkpy python 'exit 1'
mkpy py 'exit 1'
got=0
printf '{"agent_type":"sefi-agents","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' \
  | env PATH="$PYSHIM:$PATH" bash "$CBW" >/dev/null 2>&1 || got=$?
if [ "$got" -eq 0 ]; then
  ok "no working parser at all: documented fail-open preserved (exit 0)"
else
  bad "no working parser: expected fail-open exit 0, got $got"
fi
rm -rf "$PYSHIM"

unset CLAUDE_PLUGIN_ROOT

echo
echo "=== scan-placeholders.sh (proposal 1: deterministic hallucination-pattern evidence) ==="

SP="$CORE/scripts/scan-placeholders.sh"

clean_out="$(printf 'This function reads the config file and returns its parsed value.\n' | bash "$SP" - 2>&1)"
case "$clean_out" in
  *"0 total hit(s)"*) ok "a clean baseline reports zero hits" ;;
  *) bad "clean baseline reported a hit: $clean_out" ;;
esac
expect_code 0 "scan-placeholders always exits 0 on a clean baseline" \
  bash -c "printf 'clean text here' | bash '$SP' -"

uncertain_out="$(printf 'I believe that this probably works.\n' | bash "$SP" - 2>&1)"
case "$uncertain_out" in
  *"uncertain_language: 1 hit"*) ok "uncertain_language category detects a hedge on a claim" ;;
  *) bad "uncertain_language missed: $uncertain_out" ;;
esac

incomplete_out="$(printf 'TODO: implement retry logic here.\n' | bash "$SP" - 2>&1)"
case "$incomplete_out" in
  *"incomplete_implementation: 1 hit"*) ok "incomplete_implementation category detects an unresolved TODO" ;;
  *) bad "incomplete_implementation missed: $incomplete_out" ;;
esac

placeholder_out="$(printf 'This is a placeholder value for now.\n' | bash "$SP" - 2>&1)"
case "$placeholder_out" in
  *"placeholder_content: 1 hit"*) ok "placeholder_content category detects unfilled template material" ;;
  *) bad "placeholder_content missed: $placeholder_out" ;;
esac

url_out="$(printf 'See http://example.com for the docs.\n' | bash "$SP" - 2>&1)"
case "$url_out" in
  *"test_urls: 1 hit"*) ok "test_urls category detects a fixture address in delivered output" ;;
  *) bad "test_urls missed: $url_out" ;;
esac

multi_out="$(printf 'TODO: implement this\nFIXME: this is broken\nHACK: workaround for now\n' | bash "$SP" - 2>&1)"
case "$multi_out" in
  *"incomplete_implementation: 3 hit(s)"*) ok "multi-hit counting: 3 separate lines in one category counted, not just detected" ;;
  *) bad "multi-hit count wrong: $multi_out" ;;
esac

empty_out="$(printf '' | bash "$SP" - 2>&1)"
case "$empty_out" in
  *"0 total hit(s)"*) ok "empty input reports zero hits, not an error" ;;
  *) bad "empty input produced: $empty_out" ;;
esac
expect_code 0 "empty input exits 0" bash -c "printf '' | bash '$SP' -"

expect_code 0 "a nonexistent file path exits 0, not an error (evidence-only design)" \
  bash "$SP" /no/such/file/exists

# Re-break/restore proof, per qa-engineer.md item 6's own rule: temporarily disable the
# TODO pattern, confirm the assertion that depends on it now fails, then restore and
# confirm it passes again. This proves the test is actually exercising the pattern, not
# passing by construction.
SP_BAK="$(mktemp)"
cp "$SP" "$SP_BAK"
sed -i 's/"\*todo: implement\*"/"*NEVER_MATCHES_ANYTHING*"/' "$SP"
broken_out="$(printf 'TODO: implement retry logic here.\n' | bash "$SP" - 2>&1)"
case "$broken_out" in
  *"incomplete_implementation: 1 hit"*) bad "re-break did not disable the pattern -- the test proves nothing" ;;
  *) ok "re-break proof: disabling the TODO pattern makes the hit disappear as expected" ;;
esac
cp "$SP_BAK" "$SP"
rm -f "$SP_BAK"
restored_out="$(printf 'TODO: implement retry logic here.\n' | bash "$SP" - 2>&1)"
case "$restored_out" in
  *"incomplete_implementation: 1 hit"*) ok "restore proof: the pattern is back and the hit is detected again" ;;
  *) bad "restore failed -- scan-placeholders.sh was not returned to its working state: $restored_out" ;;
esac

echo
echo "=== check-structure-diff.sh (proposal 2: retro-improve's fast deterministic pre-filter) ==="

CSD="$CORE/scripts/check-structure-diff.sh"
SW="$(mktemp -d)"
cp "$CORE/agents/software-engineer.md" "$SW/before.md"

cp "$SW/before.md" "$SW/identical.md"
expect_code 0 "identical files: no structural change flagged" \
  bash "$CSD" "$SW/before.md" "$SW/identical.md"

sed 's/^managed-by: sefi-agents$/managed-by: sefi-agents\nnew-field: hello/' \
  "$SW/before.md" > "$SW/added.md"
expect_code 0 "an addition-only edit (a new frontmatter key) passes clean" \
  bash "$CSD" "$SW/before.md" "$SW/added.md"

sed 's/^tools: Read, Grep, Glob, Bash, Write, Edit, MultiEdit$/tools: Read, Grep, Glob, Write, Edit, MultiEdit/' \
  "$SW/before.md" > "$SW/stripped-tool.md"
diff_out="$(bash "$CSD" "$SW/before.md" "$SW/stripped-tool.md" 2>&1)" || true
case "$diff_out" in
  *"tools: Read, Grep, Glob, Bash"*) ok "a removed tools: entry (Bash) is flagged" ;;
  *) bad "removed tools: entry not flagged: $diff_out" ;;
esac
expect_code 1 "a stripped tool exits 1" bash "$CSD" "$SW/before.md" "$SW/stripped-tool.md"

grep -v "anti-hallucination" "$SW/before.md" > "$SW/stripped-ah.md"
expect_code 1 "a stripped anti-hallucination pointer exits 1" \
  bash "$CSD" "$SW/before.md" "$SW/stripped-ah.md"

expect_code 2 "check-structure-diff usage error on a missing file" \
  bash "$CSD" "$SW/before.md" /no/such/file
rm -rf "$SW"

echo
echo "=== routing regression re-run (reuses validate-routing.sh / routing-cases.txt, no new mechanism) ==="

VR="$CORE/scripts/ci/validate-routing.sh"
TABLE="$CORE/skills/sefi-orchestration/references/routing-table.md"
TABLE_BAK="$(mktemp)"
cp "$TABLE" "$TABLE_BAK"

# Re-break/restore, applied directly to the live fixture target: validate-routing.sh
# resolves TABLE relative to its own script location, not a passable argument, so proving
# it catches a routing regression means mutating the real file and restoring it -- the same
# discipline as scan-placeholders.sh's re-break/restore test above.
sed -i 's/| "plan X" \/ goal to spec | product-manager |/| "plan X" \/ goal to spec | knowledge-manager |/' "$TABLE"
broken_rc=0
bash "$VR" >/dev/null 2>&1 || broken_rc=$?
cp "$TABLE_BAK" "$TABLE"
rm -f "$TABLE_BAK"
if [ "$broken_rc" -ne 0 ]; then
  ok "a routing-table edit that breaks the 'plan X' fixture is caught by validate-routing.sh (exit $broken_rc)"
else
  bad "validate-routing.sh did not catch a broken 'plan X' fixture -- the re-run this plan reuses is not actually wired"
fi

restored_rc=0
bash "$VR" >/dev/null 2>&1 || restored_rc=$?
if [ "$restored_rc" -eq 0 ]; then
  ok "restore proof: routing-table.md is back and validate-routing.sh passes again"
else
  bad "restore failed -- routing-table.md was not returned to its working state (exit $restored_rc)"
fi

echo
echo "=== script-path resolution (found live: 24 bare 'scripts/x.sh' refs, no installer copied scripts/) ==="

SPR="$CORE/scripts/ci/validate-script-refs.sh"

# validate-script-refs.sh resolves its own repo root relative to its own path, not an
# argument (same discipline as validate-routing.sh's fixture), so proving it catches a
# regression means mutating a real tracked agent file and restoring it, not a scratch copy.
QA_AGENT="$CORE/agents/qa-engineer.md"
QA_BAK="$(mktemp)"
cp "$QA_AGENT" "$QA_BAK"

sed -i 's#\${CLAUDE_PLUGIN_ROOT}/scripts/gate\.sh#scripts/gate.sh#' "$QA_AGENT"
broken_rc=0
bash "$SPR" >/dev/null 2>&1 || broken_rc=$?
cp "$QA_BAK" "$QA_AGENT"
rm -f "$QA_BAK"
if [ "$broken_rc" -ne 0 ]; then
  ok "a bare (unprefixed) scripts/x.sh reference is caught by validate-script-refs.sh (exit $broken_rc)"
else
  bad "validate-script-refs.sh did not catch a bare scripts/gate.sh reference"
fi

restored_rc=0
bash "$SPR" >/dev/null 2>&1 || restored_rc=$?
if [ "$restored_rc" -eq 0 ]; then
  ok "restore proof: qa-engineer.md is back and validate-script-refs.sh passes again"
else
  bad "restore failed -- qa-engineer.md was not returned to its working state (exit $restored_rc)"
fi

# install.sh --copy: scripts/ must land at the destination and every ${CLAUDE_PLUGIN_ROOT}
# placeholder in copied agent/skill/command content must resolve to a literal path -- the
# two halves of the bug (files missing; references unresolvable) proven together.
HERMES_TMP="$(mktemp -d)"
HERMES_HOME="$HERMES_TMP" bash "$ROOT/install.sh" --target hermes --copy >/dev/null 2>&1
if [ -d "$HERMES_TMP/scripts" ] && [ -f "$HERMES_TMP/scripts/gate.sh" ]; then
  ok "install.sh --copy --target hermes places scripts/ (including gate.sh) at the destination"
else
  bad "install.sh --copy --target hermes did not place scripts/ at the destination"
fi
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$HERMES_TMP/agents" "$HERMES_TMP/skills" "$HERMES_TMP/commands" >/dev/null 2>&1; then
  bad "install.sh --copy left an unresolved \${CLAUDE_PLUGIN_ROOT} placeholder in copied agent/skill/command content"
else
  ok "install.sh --copy resolved every \${CLAUDE_PLUGIN_ROOT} placeholder to a literal path"
fi
rm -rf "$HERMES_TMP"

# Live-caught 2026-08-19 running this exact install against a real ~/.claude: a
# pre-existing skills/ (refused without --force, setting rc=1) skipped the WHOLE
# substitution pass, leaving agents/ and commands/ -- which copied successfully --
# unresolved even though resolving them never depended on skills/ succeeding. Reproduced
# here: pre-seed a conflicting skills/ dir, confirm the run reports the conflict (rc<>0),
# and confirm agents/ still gets resolved anyway.
PARTIAL_TMP="$(mktemp -d)"
mkdir -p "$PARTIAL_TMP/skills"
touch "$PARTIAL_TMP/skills/.pre-existing"
partial_rc=0
HERMES_HOME="$PARTIAL_TMP" bash "$ROOT/install.sh" --target hermes --copy >/dev/null 2>&1 || partial_rc=$?
if [ "$partial_rc" -ne 0 ] && [ -f "$PARTIAL_TMP/skills/.pre-existing" ]; then
  ok "a pre-existing skills/ is left untouched and reported as a conflict (exit $partial_rc), not silently overwritten"
else
  bad "pre-existing skills/ conflict not reproduced as expected (exit $partial_rc)"
fi
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$PARTIAL_TMP/agents" "$PARTIAL_TMP/commands" >/dev/null 2>&1; then
  bad "a skills/ conflict still skips placeholder resolution for agents/commands that DID copy -- the exact bug this test guards"
else
  ok "agents/commands still get \${CLAUDE_PLUGIN_ROOT} resolved even when skills/ conflicts and the run reports an error"
fi
rm -rf "$PARTIAL_TMP"

# install-opencode.sh is always-copy (never symlink), so the same two checks apply there.
OC_TMP="$(mktemp -d)"
OPENCODE_HOME="$OC_TMP" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1
if [ -d "$OC_TMP/scripts" ] && [ -f "$OC_TMP/scripts/gate.sh" ]; then
  ok "install-opencode.sh places scripts/ (including gate.sh) at the destination"
else
  bad "install-opencode.sh did not place scripts/ at the destination"
fi
if grep -rl '${CLAUDE_PLUGIN_ROOT}' "$OC_TMP/agents" "$OC_TMP/skills" "$OC_TMP/commands" >/dev/null 2>&1; then
  bad "install-opencode.sh left an unresolved \${CLAUDE_PLUGIN_ROOT} placeholder in copied agent/skill/command content"
else
  ok "install-opencode.sh resolved every \${CLAUDE_PLUGIN_ROOT} placeholder to a literal path"
fi
rm -rf "$OC_TMP"

echo
echo "=== install.sh --target claude wires hooks/hooks.json (live-caught 2026-08-19) ==="

# Live-caught: neither installer ever touched hooks/ at all -- a dispatched agent with
# disallowedTools: Write, Edit, MultiEdit ran a Bash write completely uncaught, because
# check-bash-write.sh (the PreToolUse hook meant to block exactly that) was never
# registered anywhere Claude Code would read it from on a fallback (non-plugin) install.
if command -v jq >/dev/null 2>&1; then
  HOOK_TMP="$(mktemp -d)"
  HOME="$HOOK_TMP" bash "$ROOT/install.sh" --target claude --copy >/dev/null 2>&1
  SETTINGS="$HOOK_TMP/.claude/settings.json"
  # Commands are quote-wrapped (step-1 fix for a space-containing resolved path), so strip
  # the embedded literal quotes before matching the suffix rather than asserting the raw
  # (now-quoted) string.
  if [ -f "$SETTINGS" ] && jq -e '.hooks.PreToolUse[0].hooks[0].command | gsub("\"";"") | endswith("scripts/check-bash-write.sh")' "$SETTINGS" >/dev/null 2>&1; then
    ok "install.sh --target claude wires check-bash-write.sh into settings.json's PreToolUse hook"
  else
    bad "install.sh --target claude did not wire check-bash-write.sh into settings.json"
  fi
  if jq -e '.hooks.SessionStart[].hooks[] | select(.command | gsub("\"";"") | endswith("scripts/inject-memory.sh"))' "$SETTINGS" >/dev/null 2>&1; then
    ok "install.sh --target claude wires inject-memory.sh into settings.json's SessionStart hook"
  else
    bad "install.sh --target claude did not wire inject-memory.sh into settings.json"
  fi
  if jq -e '.hooks.PreToolUse[0].hooks[0].command | contains("${CLAUDE_PLUGIN_ROOT}") | not' "$SETTINGS" >/dev/null 2>&1; then
    ok "the wired hook command is a resolved literal path, not the raw placeholder"
  else
    bad "the wired hook command still carries the unresolved \${CLAUDE_PLUGIN_ROOT} placeholder"
  fi

  # Merge safety: a pre-existing settings.json with unrelated hooks and permissions must
  # survive untouched, and a second run must not duplicate what the first one wired.
  mkdir -p "$HOOK_TMP/.claude"
  cat > "$SETTINGS" <<'PRESEED'
{
  "hooks": { "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "~/.claude/some-other-hook.sh" } ] } ] },
  "permissions": { "allow": ["Skill"] }
}
PRESEED
  HOME="$HOOK_TMP" bash "$ROOT/install.sh" --target claude --copy --force >/dev/null 2>&1
  HOME="$HOOK_TMP" bash "$ROOT/install.sh" --target claude --copy --force >/dev/null 2>&1
  stop_count="$(jq '.hooks.Stop | length' "$SETTINGS" 2>/dev/null)"
  pretool_count="$(jq '.hooks.PreToolUse | length' "$SETTINGS" 2>/dev/null)"
  perm_kept="$(jq -e '.permissions.allow == ["Skill"]' "$SETTINGS" >/dev/null 2>&1 && echo yes || echo no)"
  if [ "$stop_count" = "1" ] && [ "$pretool_count" = "1" ] && [ "$perm_kept" = "yes" ]; then
    ok "a pre-existing unrelated hook and permissions block survive the merge, and re-running twice does not duplicate the wired hook"
  else
    bad "hook merge is not safe/idempotent: Stop=$stop_count PreToolUse=$pretool_count permissions-kept=$perm_kept"
  fi
  rm -rf "$HOOK_TMP"
else
  echo "  SKIPPED (jq not on PATH in this environment) -- install.sh's own jq-missing warning path is exercised next instead"
fi

# jq-missing must warn plainly, not fail silently or corrupt anything -- same fail-open-
# with-honesty discipline as check-bash-write.sh's own resolver chain, applied to a
# skipped merge instead of a parse.
if command -v jq >/dev/null 2>&1; then
  JQ_REAL="$(command -v jq)"
  NOJQ_TMP="$(mktemp -d)"
  mkdir -p "$NOJQ_TMP/bin"
  for c in bash sed grep cp mkdir ln rm mv find cat env git printf mktemp basename dirname cygpath; do
    # Git Bash cannot always create symlinks, so cp is the fallback.
    p="$(command -v "$c" 2>/dev/null)" && { ln -sf "$p" "$NOJQ_TMP/bin/$c" 2>/dev/null || cp "$p" "$NOJQ_TMP/bin/$c"; }
  done
  # The sentinel exists because Git Bash builtin resolution and host-specific tool gaps
  # make the stub PATH unfaithful -- skip honestly rather than assert against an
  # environment that was never constructed.
  if PATH="$NOJQ_TMP/bin" bash -c 'command -v sed >/dev/null 2>&1 && command -v git >/dev/null 2>&1'; then
  NOJQ_HOME="$(mktemp -d)"
  nojq_out="$(PATH="$NOJQ_TMP/bin" HOME="$NOJQ_HOME" bash "$ROOT/install.sh" --target claude --copy 2>&1)" || true
  case "$nojq_out" in
    *"jq not found -- hooks/env NOT wired"*) ok "jq missing: install.sh warns plainly instead of silently skipping hooks/env wiring" ;;
    *) bad "jq-missing case did not produce the expected warning: $nojq_out" ;;
  esac
  rm -rf "$NOJQ_TMP" "$NOJQ_HOME"
  else
    echo "  SKIP: jq-missing warning case (stub PATH not constructable on this platform)"
  fi
fi

echo
echo "=== install.sh symlink-mode CLAUDE_PLUGIN_ROOT env fix (closes the 0.3.13 stated gap) ==="

# Confirmed via official docs: settings.json's "env" key is exported to every Bash tool
# call, so a symlinked (default, non-copy) install can resolve ${CLAUDE_PLUGIN_ROOT} via
# ordinary shell expansion instead of file-content rewriting, which symlink mode can't do
# without mutating the source checkout.
if command -v jq >/dev/null 2>&1; then
  ENV_TMP="$(mktemp -d)"
  HOME="$ENV_TMP" bash "$ROOT/install.sh" --target claude >/dev/null 2>&1
  ENV_SETTINGS="$ENV_TMP/.claude/settings.json"
  if [ -f "$ENV_SETTINGS" ] && jq -e --arg dest "$ENV_TMP/.claude" \
      '.env.CLAUDE_PLUGIN_ROOT == $dest' "$ENV_SETTINGS" >/dev/null 2>&1; then
    ok "a default symlink-mode install (no --copy) sets env.CLAUDE_PLUGIN_ROOT to the resolved destination"
  else
    bad "symlink-mode install did not set env.CLAUDE_PLUGIN_ROOT correctly"
  fi

  # Merge safety + idempotency for the env key specifically, mirroring the hooks proof.
  mkdir -p "$ENV_TMP/.claude"
  cat > "$ENV_SETTINGS" <<'PRESEED2'
{
  "env": { "SOME_OTHER_VAR": "keep-me" },
  "permissions": { "allow": ["Skill"] }
}
PRESEED2
  HOME="$ENV_TMP" bash "$ROOT/install.sh" --target claude --force >/dev/null 2>&1
  HOME="$ENV_TMP" bash "$ROOT/install.sh" --target claude --force >/dev/null 2>&1
  other_kept="$(jq -e '.env.SOME_OTHER_VAR == "keep-me"' "$ENV_SETTINGS" >/dev/null 2>&1 && echo yes || echo no)"
  plugin_root_set="$(jq -e --arg dest "$ENV_TMP/.claude" '.env.CLAUDE_PLUGIN_ROOT == $dest' "$ENV_SETTINGS" >/dev/null 2>&1 && echo yes || echo no)"
  if [ "$other_kept" = "yes" ] && [ "$plugin_root_set" = "yes" ]; then
    ok "a pre-existing unrelated env key survives the merge, and re-running twice does not corrupt env.CLAUDE_PLUGIN_ROOT"
  else
    bad "env merge is not safe/idempotent: other-var-kept=$other_kept plugin-root-set=$plugin_root_set"
  fi
  rm -rf "$ENV_TMP"
fi

echo
echo "=== check-citation.sh (ported from a live fabricated-citation finding, 2026-08-19) ==="

CIT="$CORE/scripts/check-citation.sh"
GATE_LINES="$(wc -l < "$CORE/scripts/gate.sh")"

expect_code 1 "a citation to a nonexistent file is flagged" \
  bash -c "echo 'verified against $CORE/scripts/nope-not-real.sh:1-5' | bash '$CIT' -"

expect_code 1 "a citation whose line range exceeds the real file's length is flagged" \
  bash -c "echo 'verified against $CORE/scripts/gate.sh:$((GATE_LINES+50))-$((GATE_LINES+60))' | bash '$CIT' -"

expect_code 0 "a citation to a real, in-bounds file:line-range passes clean" \
  bash -c "echo 'verified against $CORE/scripts/gate.sh:1-10' | bash '$CIT' -"

expect_code 0 "a single-line citation (path:NN, not just path:NN-NN) is handled" \
  bash -c "echo 'verified against $CORE/scripts/gate.sh:1' | bash '$CIT' -"

# The exact real-world case this script responds to: gate.sh:91-96 is real and in-bounds,
# and a qa-engineer verdict elsewhere cited it as proof of pytest-exit-5 tolerance that
# does not exist anywhere in those lines. This script MUST pass that citation clean --
# proving the header's honest scope limit (mechanical existence only, not semantic
# correctness) is real, not just claimed in a comment nobody re-checks.
real_case_rc=0
echo "verified against $CORE/scripts/gate.sh:91-96" | bash "$CIT" - >/dev/null 2>&1 || real_case_rc=$?
if [ "$real_case_rc" -eq 0 ]; then
  ok "the real fabricated-citation example (gate.sh:91-96, real+in-bounds+semantically wrong) passes this mechanical check -- the honest limit, demonstrated"
else
  bad "check-citation.sh flagged a real, in-bounds citation -- it should only catch IMPOSSIBLE citations, not judge semantic content (exit $real_case_rc)"
fi

echo
echo "=== inject-orchestrator-role.sh + hooks.json quoting (orchestrator-role-injection plan) ==="

HOOKS_JSON="$CORE/hooks/hooks.json"
ORCH_HOOK="$CORE/scripts/inject-orchestrator-role.sh"

# (a) every command string in hooks.json is quote-wrapped -- the step-1 fix, asserted so it
# cannot silently regress back to a bare ${CLAUDE_PLUGIN_ROOT}/... string that a harness
# substituting an unquoted path with a space would split.
if command -v jq >/dev/null 2>&1; then
  all_cmds="$(jq -r '[.. | .command? // empty] | .[]' "$HOOKS_JSON" 2>/dev/null)"
  unquoted="$(printf '%s\n' "$all_cmds" | grep -vE '^".*"$' || true)"
  if [ -n "$all_cmds" ] && [ -z "$unquoted" ]; then
    ok "every command string in hooks.json is quote-wrapped"
  else
    bad "a command string in hooks.json is not quote-wrapped: $unquoted"
  fi
else
  echo "  SKIP: hooks.json quote-wrap check (jq not installed)"
fi

# (b) a resolved command whose path contains a space executes cleanly -- proves the fix
# against the actual failure shape (the harness substituting a space-containing path
# unquoted, which the shell then splits), not just the quoting cosmetics.
SPACE_TMP="$(mktemp -d)"
SPACE_DEST="$SPACE_TMP/first word/scripts"
mkdir -p "$SPACE_DEST"
cp "$CORE/scripts/inject-memory.sh" "$SPACE_DEST/inject-memory.sh"
chmod +x "$SPACE_DEST/inject-memory.sh"
space_resolved="$(sed "s#\${CLAUDE_PLUGIN_ROOT}#$SPACE_TMP/first word#g" "$HOOKS_JSON" \
  | jq -r '.hooks.SessionStart[0].hooks[0].command')"
expect_code 0 "a resolved command whose path contains a space executes cleanly (quoted)" \
  bash -c "$space_resolved"
rm -rf "$SPACE_TMP"

# (c) inject-orchestrator-role.sh prints nothing and exits 0 when config/sefi.config.yml is
# absent -- an unrelated (non-sefi-scaffolded) project must never be told it is running
# this chain.
NOCFG_TMP="$(mktemp -d)"
nocfg_out="$(cd "$NOCFG_TMP" && bash "$ORCH_HOOK" 2>&1)"
nocfg_rc=0
( cd "$NOCFG_TMP" && bash "$ORCH_HOOK" >/dev/null 2>&1 ) || nocfg_rc=$?
if [ -z "$nocfg_out" ] && [ "$nocfg_rc" -eq 0 ]; then
  ok "inject-orchestrator-role.sh prints nothing and exits 0 with no config/sefi.config.yml"
else
  bad "inject-orchestrator-role.sh should be silent+exit 0 with no config (got rc=$nocfg_rc, output=$nocfg_out)"
fi
rm -rf "$NOCFG_TMP"

# (d) it prints the directive when config/sefi.config.yml is present.
CFG_TMP="$(mktemp -d)"
mkdir -p "$CFG_TMP/config"
echo "memory:" > "$CFG_TMP/config/sefi.config.yml"
cfg_out="$(cd "$CFG_TMP" && bash "$ORCH_HOOK" 2>&1)"
if printf '%s' "$cfg_out" | grep -q "SEFI ORCHESTRATOR ROLE"; then
  ok "inject-orchestrator-role.sh prints the directive when config/sefi.config.yml is present"
else
  bad "inject-orchestrator-role.sh did not print the directive with config present"
fi

# (d2) the directive also carries a close_out reminder -- added so a session gets nudged
# toward saving durable memory at least once, without the cost of a Stop-hook reengage
# (Claude Code's Stop hook is invisible to the model on plain stdout; forcing a reminder
# through would mean interrupting every session, however trivial, for one more turn).
if printf '%s' "$cfg_out" | grep -q "close_out"; then
  ok "inject-orchestrator-role.sh's directive also reminds toward close_out"
else
  bad "inject-orchestrator-role.sh's directive dropped the close_out reminder"
fi

# (e) its output stays within the 600-character cap.
cfg_len="$(printf '%s' "$cfg_out" | wc -c | tr -d ' ')"
if [ "$cfg_len" -le 600 ]; then
  ok "inject-orchestrator-role.sh output stays within the 600-character cap ($cfg_len chars)"
else
  bad "inject-orchestrator-role.sh output exceeds the 600-character cap ($cfg_len chars)"
fi
rm -rf "$CFG_TMP"

# (f) after install.sh --target claude against a temp $HOME, settings.json's SessionStart
# array carries BOTH hooks, and the pre-existing inject-memory.sh entry survives the merge.
if command -v jq >/dev/null 2>&1; then
  BOTH_TMP="$(mktemp -d)"
  HOME="$BOTH_TMP" bash "$ROOT/install.sh" --target claude --copy >/dev/null 2>&1
  BOTH_SETTINGS="$BOTH_TMP/.claude/settings.json"
  has_memory="no"; has_orch="no"
  if [ -f "$BOTH_SETTINGS" ]; then
    jq -e '.hooks.SessionStart[].hooks[] | select(.command | gsub("\"";"") | endswith("scripts/inject-memory.sh"))' "$BOTH_SETTINGS" >/dev/null 2>&1 && has_memory="yes"
    jq -e '.hooks.SessionStart[].hooks[] | select(.command | gsub("\"";"") | endswith("scripts/inject-orchestrator-role.sh"))' "$BOTH_SETTINGS" >/dev/null 2>&1 && has_orch="yes"
  fi
  if [ "$has_memory" = "yes" ] && [ "$has_orch" = "yes" ]; then
    ok "settings.json's SessionStart array carries both inject-memory.sh and inject-orchestrator-role.sh after install.sh --target claude"
  else
    bad "settings.json's SessionStart array is missing a hook after install.sh --target claude (memory=$has_memory orchestrator=$has_orch)"
  fi
  rm -rf "$BOTH_TMP"
else
  echo "  SKIPPED (jq not on PATH)"
fi

echo
echo "=== validate-rule-presence.sh (content-presence contract: a load-bearing rule sentence deleted or reworded past recognition while every path still resolves) ==="

RP="$CORE/scripts/ci/validate-rule-presence.sh"
RP_FIX="$CORE/scripts/ci/fixtures/rule-presence"

# The pass fixture: the registered sentence is present (and soft-wrapped in the target,
# so this also exercises the Markdown line-join step of the normalization).
expect_code 0 "a manifest whose every sentence is present exits 0" \
  bash "$RP" --manifest "$RP_FIX/pass/rule-presence.manifest" --base "$RP_FIX/pass"

# The fail fixture: the exact failure this validator exists to catch -- a registered
# sentence that is no longer in the file it names.
expect_code 1 "a manifest with a missing sentence exits 1" \
  bash "$RP" --manifest "$RP_FIX/fail/rule-presence.manifest" --base "$RP_FIX/fail"

# An empty / comment-only manifest is a setup error, not a silent pass.
RP_EMPTY="$(mktemp)"
printf '# only a comment, no rows\n' > "$RP_EMPTY"
expect_code 1 "a manifest with no registered rows exits 1" \
  bash "$RP" --manifest "$RP_EMPTY" --base "$RP_FIX/pass"
rm -f "$RP_EMPTY"

# The real manifest against the real tree must be green in this checkout.
expect_code 0 "the shipped rule-presence.manifest is satisfied by the current tree" \
  bash "$RP"

# Finding 6: a row naming a file absent under --base exits 1 -- never a silent skip of a
# row whose source file could not be opened (validate-rule-presence.sh:76-79).
expect_code 1 "a manifest row whose target file is missing exits 1" \
  bash "$RP" --manifest "$RP_FIX/missing-target/rule-presence.manifest" --base "$RP_FIX/missing-target"

# Finding 3 pin: the two halves of the registered sentence are separated by a blank line
# in the target. A whole-file normalizer bridges that gap and FALSELY reports OK; the
# paragraph-local normalizer must not, so this row misses and the run exits 1.
expect_code 1 "a sentence split across a blank line in the target is not a match (paragraph-local join)" \
  bash "$RP" --manifest "$RP_FIX/paragraph-split/rule-presence.manifest" --base "$RP_FIX/paragraph-split"

# Whitespace-only-separator pin: awk RS="" paragraph mode splits ONLY on truly empty
# lines. A separator holding a lone space (space-sep) or a lone tab (tab-sep) is a
# Markdown paragraph break too; the normalizer's leading sed must blank it so the row
# straddling it MISSES and the run exits 1. Without the sed both of these falsely pass.
expect_code 1 "a sentence split across a space-only separator line is not a match" \
  bash "$RP" --manifest "$RP_FIX/whitespace-split-space/rule-presence.manifest" --base "$RP_FIX/whitespace-split-space"
expect_code 1 "a sentence split across a tab-only separator line is not a match" \
  bash "$RP" --manifest "$RP_FIX/whitespace-split-tab/rule-presence.manifest" --base "$RP_FIX/whitespace-split-tab"

# Finding 1 regression: run-all.sh forwards --strict (or CI_STRICT=1) to every validator.
# This one has no warning tier, so it must tolerate the flag the way its siblings do --
# not reject it as an unknown argument and turn CI_STRICT=1 run-all.sh red.
expect_code 0 "--strict is accepted and ignored (parity with the siblings run-all.sh forwards it to)" \
  bash "$RP" --strict

# Finding 2 regression: a value-taking option given with no value must exit 1 AND must
# terminate. An earlier revision spun forever -- 'set -u' without '-e' left a failed
# 'shift 2' unconsumed and the 'while [ $# -gt 0 ]' loop never ended.
if command -v timeout >/dev/null 2>&1; then
  rp_hang_rc=0
  timeout 8 bash "$RP" --manifest >/dev/null 2>&1 || rp_hang_rc=$?
  if [ "$rp_hang_rc" -eq 1 ]; then
    ok "--manifest with no following value exits 1 without hanging"
  elif [ "$rp_hang_rc" -eq 124 ]; then
    bad "--manifest with no following value HUNG (timeout fired) instead of exiting 1"
  else
    bad "--manifest with no following value: expected exit 1, got $rp_hang_rc"
  fi
else
  echo "  SKIP: --manifest no-value hang guard (timeout(1) not on PATH)"
fi

# Step-3 cross-harness survival: install-opencode.sh is the one install transform that
# rewrites files. Run it against a throwaway OPENCODE_HOME, then require every registered
# sentence to still be a normalized substring of the TRANSFORMED output tree.
RP_OC="$(mktemp -d)"
# Capture the installer's own exit code FIRST. If the transform itself failed, the
# survival check below would run against a partial tree and misattribute the install
# error as "a sentence did not survive" -- assert the install succeeded before trusting
# anything downstream of it.
rp_oc_install_rc=0
OPENCODE_HOME="$RP_OC" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1 || rp_oc_install_rc=$?
if [ "$rp_oc_install_rc" -ne 0 ]; then
  bad "install-opencode.sh failed (rc=$rp_oc_install_rc) -- cross-harness survival assertion could not run"
else
  rp_oc_rc=0
  rp_oc_out="$(bash "$RP" --post-install "$RP_OC" 2>&1)" || rp_oc_rc=$?
  if [ "$rp_oc_rc" -eq 0 ]; then
    ok "every registered rule sentence survives the OpenCode agent transform ($rp_oc_out)"
  else
    bad "a registered rule sentence did not survive install-opencode.sh (rc=$rp_oc_rc): $rp_oc_out"
  fi
fi
rm -rf "$RP_OC"

echo
echo "=== validate-release-ledger.sh (Phase 2: six-surface release reconciliation, ported from astral-orchestrator release-ledger.py, MIT) ==="

RL="$CORE/scripts/ci/validate-release-ledger.sh"
RLF="$CORE/scripts/ci/fixtures/release-ledger"
# An empty --root so the on-disk cross-check (condition 2) is inert -- these fixtures
# exercise the cross-surface contradiction (condition 1) and the unobserved-surface
# warning path, both of which must hold with no repo files in reach.
RL_ROOT="$(mktemp -d)"

# ok: every surface observed and agreeing -> exit 0.
expect_code 0 "ok fixture: all six surfaces agree, exits 0" \
  bash "$RL" --ledger "$RLF/ok/ledger.md" --root "$RL_ROOT"

# contradiction: git-tag observed a version no other surface shows -> hard-fail exit 1.
expect_code 1 "contradiction fixture: two surfaces disagree for the latest version, exits 1" \
  bash "$RL" --ledger "$RLF/contradiction/ledger.md" --root "$RL_ROOT"

# incomplete: on-disk surfaces agree, the three remote surfaces never checked -> exit 0
# but every missing surface must be named in a WARN line (the signal must not be silent).
inc_out="$(bash "$RL" --ledger "$RLF/incomplete/ledger.md" --root "$RL_ROOT" 2>&1)"
inc_rc=$?
if [ "$inc_rc" -eq 0 ] && printf '%s' "$inc_out" | grep -q "WARN: surface 'github-release' is unobserved" \
   && printf '%s' "$inc_out" | grep -q "3/6 surfaces observed"; then
  ok "incomplete fixture: exits 0 with WARN lines naming each unobserved surface"
else
  bad "incomplete fixture: expected exit 0 + WARN lines, got rc=$inc_rc out=$inc_out"
fi

# condition 2: a row whose observed value contradicts the on-disk file it names must
# hard-fail even if no two ledger rows disagree with each other. Build a throwaway repo
# root whose plugin.json says 0.6.0 and a ledger row that claims it observed 0.4.0.
C2_ROOT="$(mktemp -d)"
mkdir -p "$C2_ROOT/plugins/sefi-core/.claude-plugin" "$C2_ROOT/.claude-plugin"
printf '{\n  "version": "0.6.0"\n}\n' > "$C2_ROOT/plugins/sefi-core/.claude-plugin/plugin.json"
printf '{ "metadata": { "version": "0.6.0" }, "plugins": [ { "version": "0.6.0" } ] }\n' > "$C2_ROOT/.claude-plugin/marketplace.json"
printf '# Changelog\n\n## [0.6.0] - 2026-09-01\n' > "$C2_ROOT/CHANGELOG.md"
cat > "$C2_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.4.0 | match | stale row | x | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | 0.4.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | 0.4.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | 0.4.0 | match | ok | x | 2026-09-01T00:00:00Z |
LEDGER
c2_out="$(bash "$RL" --ledger "$C2_ROOT/ledger.md" --root "$C2_ROOT" 2>&1)"
c2_rc=$?
if [ "$c2_rc" -eq 1 ] && printf '%s' "$c2_out" | grep -q "plugin.json observed 0.4.0"; then
  ok "condition 2: a row's observed value contradicting the on-disk plugin.json hard-fails"
else
  bad "condition 2: expected exit 1 naming the plugin.json contradiction, got rc=$c2_rc out=$c2_out"
fi
rm -rf "$C2_ROOT"

# condition 2, CHANGELOG arm (distinct from the plugin.json arm above): a changelog row
# whose observed value contradicts the CHANGELOG.md first versioned heading on disk must
# hard-fail for THAT reason. Every other surface is `unobserved`, so hard-fail 1 (two
# observed surfaces disagree) cannot fire -- only the `changelog)` arm of the on-disk
# cross-check can produce this exit 1. Deleting that arm makes this test go green->red.
C2_CL_ROOT="$(mktemp -d)"
mkdir -p "$C2_CL_ROOT/plugins/sefi-core/.claude-plugin" "$C2_CL_ROOT/.claude-plugin"
printf '{\n  "version": "0.6.0"\n}\n' > "$C2_CL_ROOT/plugins/sefi-core/.claude-plugin/plugin.json"
printf '{ "metadata": { "version": "0.6.0" }, "plugins": [ { "version": "0.6.0" } ] }\n' > "$C2_CL_ROOT/.claude-plugin/marketplace.json"
printf '# Changelog\n\n## [Unreleased] - 2026-09-02\n\n## [0.6.0] - 2026-09-01\n' > "$C2_CL_ROOT/CHANGELOG.md"
cat > "$C2_CL_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.5.0 | match | stale row | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
c2cl_out="$(bash "$RL" --ledger "$C2_CL_ROOT/ledger.md" --root "$C2_CL_ROOT" 2>&1)"
c2cl_rc=$?
if [ "$c2cl_rc" -eq 1 ] && printf '%s' "$c2cl_out" | grep -q "changelog observed 0.5.0" \
   && ! printf '%s' "$c2cl_out" | grep -q "surfaces disagree"; then
  ok "condition 2 CHANGELOG arm: a changelog row vs the on-disk top heading hard-fails on its own"
else
  bad "condition 2 CHANGELOG arm: expected exit 1 naming the changelog contradiction and NO hard-fail-1, got rc=$c2cl_rc out=$c2cl_out"
fi
rm -rf "$C2_CL_ROOT"

# condition 2, marketplace.json arm (distinct again): a marketplace.json row whose observed
# value matches neither on-disk occurrence must hard-fail for THAT reason, with every other
# surface `unobserved` so hard-fail 1 cannot fire. Deleting the `marketplace.json)` arm
# makes this test go green->red.
C2_MP_ROOT="$(mktemp -d)"
mkdir -p "$C2_MP_ROOT/plugins/sefi-core/.claude-plugin" "$C2_MP_ROOT/.claude-plugin"
printf '{\n  "version": "0.6.0"\n}\n' > "$C2_MP_ROOT/plugins/sefi-core/.claude-plugin/plugin.json"
printf '{ "metadata": { "version": "0.6.0" }, "plugins": [ { "version": "0.6.0" } ] }\n' > "$C2_MP_ROOT/.claude-plugin/marketplace.json"
printf '# Changelog\n\n## [0.6.0] - 2026-09-01\n' > "$C2_MP_ROOT/CHANGELOG.md"
cat > "$C2_MP_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.4.0 | match | stale row | x | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
c2mp_out="$(bash "$RL" --ledger "$C2_MP_ROOT/ledger.md" --root "$C2_MP_ROOT" 2>&1)"
c2mp_rc=$?
if [ "$c2mp_rc" -eq 1 ] && printf '%s' "$c2mp_out" | grep -q "marketplace.json observed 0.4.0" \
   && ! printf '%s' "$c2mp_out" | grep -q "surfaces disagree"; then
  ok "condition 2 marketplace.json arm: a marketplace.json row vs both on-disk occurrences hard-fails on its own"
else
  bad "condition 2 marketplace.json arm: expected exit 1 naming the marketplace.json contradiction and NO hard-fail-1, got rc=$c2mp_rc out=$c2mp_out"
fi
rm -rf "$C2_MP_ROOT"

# marketplace.json self-disagreement: metadata.version and plugins[0].version differ FROM
# EACH OTHER on disk. Must hard-fail regardless of what the ledger row observed -- here the
# ledger row observes 0.6.0, which matches ONE of the two occurrences, so the old
# sort -u membership test would have passed it.
MP_SELF_ROOT="$(mktemp -d)"
mkdir -p "$MP_SELF_ROOT/plugins/sefi-core/.claude-plugin" "$MP_SELF_ROOT/.claude-plugin"
printf '{\n  "version": "0.6.0"\n}\n' > "$MP_SELF_ROOT/plugins/sefi-core/.claude-plugin/plugin.json"
printf '{ "metadata": { "version": "0.6.0" }, "plugins": [ { "version": "0.6.1" } ] }\n' > "$MP_SELF_ROOT/.claude-plugin/marketplace.json"
printf '# Changelog\n\n## [0.6.0] - 2026-09-01\n' > "$MP_SELF_ROOT/CHANGELOG.md"
cat > "$MP_SELF_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
mps_out="$(bash "$RL" --ledger "$MP_SELF_ROOT/ledger.md" --root "$MP_SELF_ROOT" 2>&1)"
mps_rc=$?
if [ "$mps_rc" -eq 1 ] && printf '%s' "$mps_out" | grep -q "marketplace.json self-disagreement"; then
  ok "marketplace.json self-disagreement: the two on-disk occurrences differing from each other hard-fails even when the ledger row matches one of them"
else
  bad "marketplace.json self-disagreement: expected exit 1 naming the self-disagreement, got rc=$mps_rc out=$mps_out"
fi
rm -rf "$MP_SELF_ROOT"

# a non-empty version cell that is not a semver must hard-fail, symmetric with the unknown
# surface / unknown status checks -- not silently drop the row out of latest/latest_rows.
BADVER_ROOT="$(mktemp -d)"
cat > "$BADVER_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| TBD | changelog | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
bv_out="$(bash "$RL" --ledger "$BADVER_ROOT/ledger.md" --root "$BADVER_ROOT" 2>&1)"
bv_rc=$?
if [ "$bv_rc" -eq 1 ] && printf '%s' "$bv_out" | grep -q "unparseable version cell 'TBD'"; then
  ok "malformed version cell: a non-semver version token among valid rows hard-fails (does not silently exempt the row)"
else
  bad "malformed version cell: expected exit 1 naming the unparseable cell, got rc=$bv_rc out=$bv_out"
fi
# an ALL-malformed version column keeps the pre-existing 'no semantic version found' exit 1.
cat > "$BADVER_ROOT/allbad.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| draft | plugin.json | x | x | match | ok | x | 2026-09-01T00:00:00Z |
| TBD | changelog | x | x | match | ok | x | 2026-09-01T00:00:00Z |
LEDGER
ab_out="$(bash "$RL" --ledger "$BADVER_ROOT/allbad.md" --root "$BADVER_ROOT" 2>&1)"
ab_rc=$?
if [ "$ab_rc" -eq 1 ] && printf '%s' "$ab_out" | grep -q "no semantic version found in the ledger's version column"; then
  ok "all-malformed version column: still exits 1 with 'no semantic version found' (pre-existing behavior kept)"
else
  bad "all-malformed version column: expected exit 1 with 'no semantic version found', got rc=$ab_rc out=$ab_out"
fi
rm -rf "$BADVER_ROOT"

# hard-fail 1 is per version GROUP across the whole append-only ledger, not latest-only:
# the latest group (0.6.0) is internally consistent, but a HISTORICAL group (0.5.0) has two
# surfaces observing contradicting versions. A latest-only check would exit 0 here.
PVG_ROOT="$(mktemp -d)"
cat > "$PVG_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | marketplace.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | changelog | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-release | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | github-marketplace-index | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.5.0 | plugin.json | 0.5.0 | 0.5.0 | match | ok | x | 2026-08-01T00:00:00Z |
| 0.5.0 | git-tag | 0.5.0 | 0.5.1 | mismatch | historical drift never reconciled | x | 2026-08-01T00:00:00Z |
LEDGER
pvg_out="$(bash "$RL" --ledger "$PVG_ROOT/ledger.md" --root "$PVG_ROOT" 2>&1)"
pvg_rc=$?
if [ "$pvg_rc" -eq 1 ] && printf '%s' "$pvg_out" | grep -q "version claim 0.5.0"; then
  ok "per-version-group contradiction: a historical (non-latest) version group with disagreeing surfaces hard-fails"
else
  bad "per-version-group contradiction: expected exit 1 naming the 0.5.0 group, got rc=$pvg_rc out=$pvg_out"
fi
rm -rf "$PVG_ROOT"

# FIX 1 -- partial-semver escape: norm_semver is anchored end-to-end (^v?X.Y.Z$), so a
# version cell that is ALMOST a semver (a 4th segment, a -rcN suffix) no longer prefix-
# matches to a truncated version that then silently fails the v==L / v==G equality checks
# and drops the row out of hard-fail 1, hard-fail 2, and the N/6 count. Each such cell must
# trip the non-empty version guard and exit 1 naming the exact cell text.
PSV_ROOT="$(mktemp -d)"
for badv in "0.6.0-rc1" "1.2.3.4" "0.5.2.1"; do
  cat > "$PSV_ROOT/ledger.md" <<LEDGER
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| $badv | changelog | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
LEDGER
  psv_out="$(bash "$RL" --ledger "$PSV_ROOT/ledger.md" --root "$PSV_ROOT" 2>&1)"
  psv_rc=$?
  if [ "$psv_rc" -eq 1 ] && printf '%s' "$psv_out" | grep -qF "unparseable version cell '$badv'"; then
    ok "partial-semver '$badv': exits 1 naming the cell (no prefix-match escape)"
  else
    bad "partial-semver '$badv': expected exit 1 naming the cell, got rc=$psv_rc out=$psv_out"
  fi
done
# the exact forms still parse: a bare semver, a v-prefixed one, and a two-digit segment.
cat > "$PSV_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.5.2 | plugin.json | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
| v0.5.2 | changelog | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.10.0 | git-tag | 0.10.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
psv_ok_out="$(bash "$RL" --ledger "$PSV_ROOT/ledger.md" --root "$PSV_ROOT" 2>&1)"
psv_ok_rc=$?
if [ "$psv_ok_rc" -eq 0 ] && printf '%s' "$psv_ok_out" | grep -q "latest 0.10.0"; then
  ok "exact semver forms (0.5.2, v0.5.2, 0.10.0) still parse; latest resolves to 0.10.0"
else
  bad "exact semver forms: expected exit 0 with latest 0.10.0, got rc=$psv_ok_rc out=$psv_ok_out"
fi
rm -rf "$PSV_ROOT"

# leading-zero semver: each numeric component is (0|[1-9][0-9]*), so a version cell with a
# leading-zero component (00.5.2, 01.0.0, 0.05.2, 1.2.03) fails to parse and must trip the
# unparseable-version hard-fail exit 1 naming the cell -- otherwise 00.5.2 and 0.5.2 would
# normalize into two distinct version groups and hard-fail 1 would never compare them.
LZ_ROOT="$(mktemp -d)"
for badv in "00.5.2" "01.0.0" "0.05.2" "1.2.03"; do
  cat > "$LZ_ROOT/ledger.md" <<LEDGER
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.5.2 | plugin.json | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
| $badv | changelog | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
LEDGER
  lz_out="$(bash "$RL" --ledger "$LZ_ROOT/ledger.md" --root "$LZ_ROOT" 2>&1)"
  lz_rc=$?
  if [ "$lz_rc" -eq 1 ] && printf '%s' "$lz_out" | grep -qF "unparseable version cell '$badv'"; then
    ok "leading-zero version '$badv': exits 1 naming the cell (no phantom version group)"
  else
    bad "leading-zero version '$badv': expected exit 1 naming the cell, got rc=$lz_rc out=$lz_out"
  fi
done
# multi-digit components without a leading zero still parse.
cat > "$LZ_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.5.2 | plugin.json | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.10.0 | changelog | 0.10.0 | 0.10.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 1.20.3 | git-tag | 1.20.3 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
lz_ok_out="$(bash "$RL" --ledger "$LZ_ROOT/ledger.md" --root "$LZ_ROOT" 2>&1)"
lz_ok_rc=$?
if [ "$lz_ok_rc" -eq 0 ] && printf '%s' "$lz_ok_out" | grep -q "latest 1.20.3"; then
  ok "no-leading-zero multi-digit forms (0.10.0, 1.20.3) still parse; latest resolves to 1.20.3"
else
  bad "multi-digit semver forms: expected exit 0 with latest 1.20.3, got rc=$lz_ok_rc out=$lz_ok_out"
fi
rm -rf "$LZ_ROOT"

# FIX 4 -- a legal GFM alignment separator row (colons around the dashes) must be
# recognized as a separator, not parsed as a data row (which produced spurious
# unknown-surface / unknown-status errors).
ALN_ROOT="$(mktemp -d)"
cat > "$ALN_ROOT/ledger.md" <<'LEDGER'
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|:--------|:-------:|---------:|:--------:|:------:|:---------|:------------------:|-----------:|
| 0.6.0 | plugin.json | 0.6.0 | 0.6.0 | match | ok | x | 2026-09-01T00:00:00Z |
| 0.6.0 | git-tag | 0.6.0 | unobserved | unobserved | not checked | x | 2026-09-01T00:00:00Z |
LEDGER
aln_out="$(bash "$RL" --ledger "$ALN_ROOT/ledger.md" --root "$ALN_ROOT" 2>&1)"
aln_rc=$?
if [ "$aln_rc" -eq 0 ] && ! printf '%s' "$aln_out" | grep -q "ERROR:"; then
  ok "GFM alignment separator row is skipped, not parsed as data (no spurious errors)"
else
  bad "GFM alignment separator: expected exit 0 with no ERROR lines, got rc=$aln_rc out=$aln_out"
fi
rm -rf "$ALN_ROOT"

# FIX 1 (release-0.5.1 pass) -- the separator-row skip is a WHOLE-ROW test, not a version-
# column test. A real data row whose version cell alone is :-: / --: / :-- (all valid
# alignment-marker spellings) must NOT be discarded as a table separator: it has to reach
# norm_semver, fail the exact-semver guard, and hard-fail exit 1 naming the cell. A revert
# to the version-column-only skip ($2 ~ /^:?-+:?$/) silently drops the row and returns
# exit 0 "OK" even while it carries a disk-contradicting observed value -- this catches that.
DSEP_ROOT="$(mktemp -d)"
for badv in ":-:" "--:" ":--"; do
  cat > "$DSEP_ROOT/ledger.md" <<LEDGER
| version | surface | expected | observed | status | evidence | common-false-proof | observed-at |
|---------|---------|----------|----------|--------|----------|--------------------|------------|
| 0.5.2 | plugin.json | 0.5.2 | 0.5.2 | match | ok | x | 2026-09-01T00:00:00Z |
| $badv | plugin.json | 0.5.2 | 0.4.0 | mismatch | fabricated -- version cell is an alignment marker | x | 2026-09-01T00:00:00Z |
LEDGER
  dsep_out="$(bash "$RL" --ledger "$DSEP_ROOT/ledger.md" --root "$DSEP_ROOT" 2>&1)"
  dsep_rc=$?
  if [ "$dsep_rc" -eq 1 ] && printf '%s' "$dsep_out" | grep -qF "unparseable version cell '$badv'"; then
    ok "data row with version cell '$badv' is NOT skipped as a separator; hard-fails exit 1 naming the cell"
  else
    bad "data row version cell '$badv': expected exit 1 naming the cell (row must not be dropped), got rc=$dsep_rc out=$dsep_out"
  fi
done
rm -rf "$DSEP_ROOT"

# FIX 3 -- joined-form options (--ledger=PATH / --root=DIR) must be parsed, not dropped to
# the *) shift catch-all where the script would silently validate the DEFAULT ledger.
expect_code 0 "joined --ledger=PATH / --root=DIR parse like the spaced form (ok fixture)" \
  bash "$RL" "--ledger=$RLF/ok/ledger.md" "--root=$RL_ROOT"
jf_out="$(bash "$RL" "--ledger=$RL_ROOT/does-not-exist.md" "--root=$RL_ROOT" 2>&1)"
jf_rc=$?
if [ "$jf_rc" -eq 1 ] && printf '%s' "$jf_out" | grep -q "release ledger not found"; then
  ok "joined --ledger=PATH resolves the given path (missing file -> exit 1, not a silent default pass)"
else
  bad "joined --ledger=PATH: expected exit 1 'release ledger not found', got rc=$jf_rc out=$jf_out"
fi
expect_code 1 "an empty joined --ledger= value exits 1" \
  bash "$RL" "--ledger="
expect_code 1 "an unrecognized joined option (--bogus=1) exits 1, not silently ignored" \
  bash "$RL" "--bogus=1" --ledger "$RLF/ok/ledger.md" --root "$RL_ROOT"

# a missing ledger file is exit 1, not a silent pass.
expect_code 1 "a missing ledger path exits 1" \
  bash "$RL" --ledger "$RL_ROOT/does-not-exist.md" --root "$RL_ROOT"

# a missing --ledger / --root value must fail fast (exit 1), never spin forever on the
# arg loop. The `timeout` wrapper is a defensive bound for a HYPOTHETICAL future refactor
# that removes BOTH the `[ $# -ge 2 ]` guard AND the `set -u` protection -- only that
# combination could actually hang. As the script stands today (`set -u`, no `set -e`), a
# reverted guard makes `$2` an unbound-variable error that exits non-zero immediately, not
# an infinite loop. So this assertion pins exit-1-on-missing-value, but does NOT by itself
# prove the no-hang property; `set -u` alone already gives the fast non-zero exit.
# If timeout(1) is unavailable, SKIP rather than run an unbounded command.
if command -v timeout >/dev/null 2>&1; then
  expect_code 1 "a bare --ledger with no value exits 1 (no infinite loop)" \
    timeout 8 bash "$RL" --ledger
  expect_code 1 "a bare --root with no value exits 1 (no infinite loop)" \
    timeout 8 bash "$RL" --root
else
  echo "  SKIP: bare --ledger / --root no-hang assertions (timeout(1) not available on this platform)"
fi

rm -rf "$RL_ROOT"

echo
echo "=== check-route.sh (Phase 3 deferred half: LIVE Codex requested-vs-observed route) ==="

# check-route.sh is post-dispatch, not a CI validator -- it lives in scripts/, not
# scripts/ci/, and is exercised here, never from run-all.sh's validators list. It is now a
# thin interpreter-resolving shim over check-route.py (stdlib Python 3.11+, real json.loads
# per rollout line + top-level dict access only). The live match/mismatch/invalid path is
# CODEX-ONLY: claude-code stays `unavailable`, opencode/hermes stay `not-applicable` (every
# tier resolves to `flexible`).
#
# The .sh shim drives the sentinel / thread-id / non-Codex / interpreter-skip cases below.
# Because the shim forces argument 3 and beyond to be POSITIONAL with an argparse `--`
# end-of-options marker (so an unquoted $CODEX_THREAD_ID cannot smuggle --rollout-file
# through the supported entrypoint), the rollout-fixture verdict cases cannot go through the
# shim any more -- they call check-route.py DIRECTLY (the contributor-test path), guarded on
# a usable python3/python 3.11+.
CRT="$CORE/scripts/check-route.sh"
CRF="$CORE/scripts/ci/fixtures/check-route"
CRPY="$CORE/scripts/check-route.py"
PYBIN=""
for _c in python3 python; do
  command -v "$_c" >/dev/null 2>&1 || continue
  "$_c" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1 || continue
  PYBIN="$_c"; break
done
[ -n "$PYBIN" ] || echo "  SKIP: no python3/python 3.11+ for direct check-route.py cases"

# --- still-valid non-Codex cases, through the .sh shim ------------------------------

# claude-code: the CLI reports no per-agent model/usage -> unavailable, nonzero.
crt_out="$(sh "$CRT" claude-code mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"unavailable"'*'harness-exposes-no-route-readback'*)
    [ "$crt_rc" -ne 0 ] && ok "claude-code mid - -> unavailable, exit $crt_rc" \
      || bad "claude-code reported unavailable but exited 0" ;;
  *) bad "claude-code did not report unavailable: $crt_out" ;;
esac

# opencode: every tier resolves to the 'flexible' sentinel (model-map.yml) -> not-applicable, exit 0.
crt_out="$(sh "$CRT" opencode mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"not-applicable"'*)
    [ "$crt_rc" -eq 0 ] && ok "opencode mid - -> not-applicable, exit 0" \
      || bad "opencode not-applicable but nonzero exit $crt_rc" ;;
  *) bad "opencode did not report not-applicable: $crt_out" ;;
esac

# hermes: every tier resolves to 'flexible' too -> not-applicable, exit 0.
crt_out="$(sh "$CRT" hermes mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"not-applicable"'*)
    [ "$crt_rc" -eq 0 ] && ok "hermes mid - -> not-applicable, exit 0" \
      || bad "hermes not-applicable but nonzero exit $crt_rc" ;;
  *) bad "hermes did not report not-applicable: $crt_out" ;;
esac

# A non-printable character in ANY argument -> exit 2, and NO JSON status line.
crt_out="$(sh "$CRT" codex "$(printf 'mid\007')" - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status"'*) bad "a non-printable arg reached a JSON status line -- must exit 2, no JSON: $crt_out" ;;
  *)
    [ "$crt_rc" -eq 2 ] && ok "a non-printable arg -> exit 2, no JSON line" \
      || bad "a non-printable arg expected exit 2, got $crt_rc: $crt_out" ;;
esac

# An unknown harness -> exit 2, and NO JSON status line.
crt_out="$(sh "$CRT" frobnicate mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status"'*) bad "an unknown harness reached a JSON status line -- must exit 2, no JSON: $crt_out" ;;
  *)
    [ "$crt_rc" -eq 2 ] && ok "an unknown harness -> exit 2, no JSON line" \
      || bad "an unknown harness expected exit 2, got $crt_rc: $crt_out" ;;
esac

# A usage error (wrong arg count) is exit 2, not a JSON status line.
expect_code 2 "check-route.sh with too few args is a usage error" \
  sh "$CRT" codex mid

# --- LIVE Codex verdicts: DIRECT to check-route.py (contributor-test path) -----------
# `model-for.sh codex mid` resolves to gpt-5.6-terra / high (config/model-map.yml:59-68);
# the fixtures under $CRF are built to that baseline. A rollout file is fed via the hidden
# `--rollout-file` option -- reachable ONLY by a direct `check-route.py` call, since the
# shim now forces argument 3+ positional with an argparse `--` marker (an attacker-set
# $CODEX_THREAD_ID, quoted or not, cannot reach --rollout-file). The POSITIONAL 3rd arg is
# still never file-auto-detected.
if [ -n "$PYBIN" ]; then

crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/match/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*)
    [ "$crt_rc" -eq 0 ] && ok "codex mid <match fixture> -> match, exit 0" \
      || bad "codex match but exit $crt_rc" ;;
  *) bad "codex <match fixture> did not report match: $crt_out" ;;
esac

crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/mismatch/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"mismatch"'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <mismatch fixture> -> mismatch, exit $crt_rc (STOP rule fires)" \
      || bad "codex mismatch but exit 0 -- the orchestrator STOP rule would not fire" ;;
  *) bad "codex <mismatch fixture> did not report mismatch: $crt_out" ;;
esac

# invalid, one per shape, asserting the reason substring for each.
for pair in \
  "invalid-not-json:rollout-unreadable" \
  "invalid-no-turn-context:turn-context-missing" \
  "invalid-two-turn-context:turn-context-malformed"; do
  fx="${pair%%:*}"; why="${pair#*:}"
  crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/$fx/rollout.jsonl" 2>&1)"; crt_rc=$?
  case "$crt_out" in
    *'"status":"invalid"'*"$why"*)
      [ "$crt_rc" -ne 0 ] && ok "codex mid <$fx> -> invalid / $why, exit $crt_rc" \
        || bad "codex <$fx> invalid but exit 0" ;;
    *) bad "codex <$fx> did not report invalid / $why: $crt_out" ;;
  esac
done

# A rollout whose only content is a >4300-digit JSON integer raises a bare ValueError
# (not JSONDecodeError) inside json.loads; deep nesting would raise RecursionError. The
# widened except catches both -> one `invalid` / `rollout-unreadable` JSON line, exit
# non-zero, NEVER an uncaught traceback that would print the interpreter's absolute path.
HUGEINT="$(mktemp)"
awk 'BEGIN { s=""; for (i=0;i<5000;i++) s=s "9"; print s }' > "$HUGEINT"
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$HUGEINT" 2>&1)"; crt_rc=$?
hugeint_lines="$(printf '%s\n' "$crt_out" | grep -c .)"
case "$crt_out" in
  *Traceback*|*'check-route.py"'*)
    bad "a 5000-digit-int rollout produced a traceback instead of an invalid JSON line: $crt_out" ;;
  *'"status":"invalid"'*'rollout-unreadable'*)
    if [ "$crt_rc" -ne 0 ] && [ "$hugeint_lines" -eq 1 ]; then
      ok "a 5000-digit-int rollout -> invalid / rollout-unreadable, one JSON line, exit $crt_rc, no traceback"
    else
      bad "5000-digit-int rollout: exit $crt_rc, $hugeint_lines line(s): $crt_out"
    fi ;;
  *) bad "5000-digit-int rollout did not report invalid / rollout-unreadable: $crt_out" ;;
esac
rm -f "$HUGEINT"

# --- the top-level-only turn_context filter: two decoy CLASSES pin it ----------------
# The filter (check-route.py: iterate lines, keep only records whose TOP-LEVEL
# type=="turn_context" and payload is a dict) is the whole security premise.
#
# CLASS 1 -- substring-scan / nested-key-confusion. FOUR flattened-shape decoys
# (`decoy-nested-model-string`, `decoy-nested-turn-context-obj`, `decoy-nested-after-real`,
# `decoy-only-nested`) pin it: a real json.loads never treats a nested `"model"` string as
# a key, and the nested `turn_context` objects here are FLATTENED
# (`{"type":"turn_context","model":..,"effort":..}` with no `payload` key), so even a
# recursive descent that KEPT the parser's 3-clause predicate would walk past them. They
# stay valid JSON-parse-vs-substring regression cases; they are NOT load-bearing against a
# faithful recursive descent.
#
# CLASS 2 -- recursive descent. TWO real-shape fixtures
# (`decoy-realshape-nested-after-real`, `decoy-realshape-only-nested`) whose nested decoy is
# an EXACT `{"type":"turn_context","payload":{"model":..,"effort":..}}` record -- the shape
# the parser's predicate accepts. A descent that preserved the payload-dict clause would
# read the nested route and redden their assertions (verified by hand: descend keeping all
# 3 clauses, run this suite, confirm a real-shape assertion goes RED, revert).

# Class 1, decoy 1: a free-text string field literally containing "model":"gpt-5.6-sol"
# while the real last turn_context payload says gpt-5.6-luna. json.loads never treats that
# nested string as a key -> must be `mismatch`, NEVER a wrong `match`.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-nested-model-string/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*) bad "DECOY FAIL-OPEN: nested \"model\" string produced a wrong match: $crt_out" ;;
  *'"status":"mismatch"'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <decoy-nested-model-string> -> mismatch (no fail-open), exit $crt_rc" \
      || bad "decoy-nested-model-string mismatch but exit 0" ;;
  *) bad "decoy-nested-model-string did not report mismatch: $crt_out" ;;
esac

# Class 1, decoy 2: a non-turn_context top-level line (type=="response_item") whose payload
# nests a FLATTENED turn_context object with a downgraded model, while the real last
# top-level turn_context says terra/high. Top-level-only dict access -> must `match` the
# REAL route.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-nested-turn-context-obj/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"mismatch"'*|*'"status":"invalid"'*)
    bad "DECOY FAIL: descended into the nested turn_context object instead of the real route: $crt_out" ;;
  *'"status":"match"'*)
    [ "$crt_rc" -eq 0 ] && ok "codex mid <decoy-nested-turn-context-obj> -> match on the REAL route, exit 0" \
      || bad "decoy-nested-turn-context-obj match but exit $crt_rc" ;;
  *) bad "decoy-nested-turn-context-obj did not report match: $crt_out" ;;
esac

# Class 1, decoy 3: a REAL top-level turn_context with a DOWNGRADED model
# (gpt-5.6-luna/medium), FOLLOWED by a later non-turn_context line whose payload nests a
# FLATTENED turn_context carrying the EXPECTED good model (terra/high). Top-level-only ->
# the last TOP-LEVEL turn_context is luna/medium -> `mismatch`.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-nested-after-real/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*) bad "DECOY FAIL-OPEN: descended past the real downgraded route to a nested good model: $crt_out" ;;
  *'"status":"mismatch"'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <decoy-nested-after-real> -> mismatch on the REAL downgraded route, exit $crt_rc" \
      || bad "decoy-nested-after-real mismatch but exit 0" ;;
  *) bad "decoy-nested-after-real did not report mismatch: $crt_out" ;;
esac

# Class 1, decoy 4: NO top-level turn_context at all -- the only turn_context objects are
# FLATTENED and nested in payload.parent_context. Top-level-only -> `invalid` /
# `turn-context-missing`.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-only-nested/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*|*'"status":"mismatch"'*)
    bad "DECOY FAIL: descended into a nested-only turn_context instead of reporting it missing: $crt_out" ;;
  *'"status":"invalid"'*'turn-context-missing'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <decoy-only-nested> -> invalid / turn-context-missing, exit $crt_rc" \
      || bad "decoy-only-nested invalid but exit 0" ;;
  *) bad "decoy-only-nested did not report invalid / turn-context-missing: $crt_out" ;;
esac

# Class 2, real-shape 1 (load-bearing vs recursive descent): a REAL top-level turn_context
# with a DOWNGRADED payload (gpt-5.6-luna/medium), FOLLOWED by a non-turn_context line whose
# payload nests an EXACT-SHAPE `{"type":"turn_context","payload":{model,effort}}` record
# carrying the EXPECTED good model (terra/high). Top-level-only -> the last TOP-LEVEL
# turn_context is luna/medium -> `mismatch`. A faithful recursive descent (all 3 clauses
# kept) would pick up the nested terra/high as "last" and wrongly report `match` -- this
# assertion reddens under that mutation.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-realshape-nested-after-real/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*) bad "DECOY FAIL-OPEN: descended past the real downgraded route to a nested real-shape good model: $crt_out" ;;
  *'"status":"mismatch"'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <decoy-realshape-nested-after-real> -> mismatch on the REAL downgraded route, exit $crt_rc" \
      || bad "decoy-realshape-nested-after-real mismatch but exit 0" ;;
  *) bad "decoy-realshape-nested-after-real did not report mismatch: $crt_out" ;;
esac

# Class 2, real-shape 2 (load-bearing vs recursive descent): NO top-level turn_context; the
# only turn_context records are EXACT-SHAPE and nested under payload.parent_context /
# payload.inner. Top-level-only -> `invalid` / `turn-context-missing`. A faithful recursive
# descent would find a nested real-shape record and emit `match` (or `mismatch` if it were
# downgraded) instead -- either verdict reddens this assertion.
crt_out="$("$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/decoy-realshape-only-nested/rollout.jsonl" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"match"'*|*'"status":"mismatch"'*)
    bad "DECOY FAIL: descended into a nested-only real-shape turn_context instead of reporting it missing: $crt_out" ;;
  *'"status":"invalid"'*'turn-context-missing'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid <decoy-realshape-only-nested> -> invalid / turn-context-missing, exit $crt_rc" \
      || bad "decoy-realshape-only-nested invalid but exit 0" ;;
  *) bad "decoy-realshape-only-nested did not report invalid / turn-context-missing: $crt_out" ;;
esac

else
  echo "  SKIP: LIVE Codex rollout-verdict + decoy cases (no direct python3/python 3.11+)"
fi

# thread-id placeholder / invalid.
crt_out="$(sh "$CRT" codex mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"unavailable"'*'thread-id-unavailable'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid - -> unavailable / thread-id-unavailable, exit $crt_rc" \
      || bad "codex mid - unavailable but exit 0" ;;
  *) bad "codex mid - did not report unavailable / thread-id-unavailable: $crt_out" ;;
esac

crt_out="$(sh "$CRT" codex mid not-a-uuid 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"invalid"'*'thread-id-invalid'*)
    [ "$crt_rc" -ne 0 ] && ok "codex mid not-a-uuid -> invalid / thread-id-invalid, exit $crt_rc" \
      || bad "codex mid not-a-uuid invalid but exit 0" ;;
  *) bad "codex mid not-a-uuid did not report invalid / thread-id-invalid: $crt_out" ;;
esac

# FIX A regression -- the shim forces argument 3+ POSITIONAL with an argparse `--` marker,
# so a call site that expands $CODEX_THREAD_ID UNQUOTED cannot smuggle --rollout-file
# through the supported entrypoint and force a `match`/exit 0 from an attacker-authored
# rollout. The UNQUOTED expansion word-splits into `- --rollout-file X` -> three positionals
# after `--` while `record` takes one -> argparse "unrecognized arguments" -> exit 2, no
# JSON, fails closed.
_smuggle="- --rollout-file $CRF/match/rollout.jsonl"
crt_out="$(sh "$CRT" codex mid $_smuggle 2>&1)"; crt_rc=$?   # deliberately UNQUOTED $_smuggle
case "$crt_out" in
  *'"status":"match"'*) bad "SMUGGLE: an unquoted \$CODEX_THREAD_ID expansion injected --rollout-file through the shim -> wrong match: $crt_out" ;;
  *)
    [ "$crt_rc" -eq 2 ] && ok "shim forces arg 3+ positional: unquoted '- --rollout-file X' -> exit 2, no match" \
      || bad "smuggle attempt: expected exit 2, got $crt_rc: $crt_out" ;;
esac

# Slot-1/2 twin: the shim puts `--` before EVERY positional, so a leading-dash word that
# word-splits into the harness/tier slot cannot smuggle --rollout-file either. Load-bearing
# against a refactor back to arg-1/arg-2 capture (bare `exec "$INTERP" "$PY" "$@"`).
_smuggle12="--rollout-file $CRF/match/rollout.jsonl codex mid -"
crt_out="$(sh "$CRT" $_smuggle12 2>&1)"; crt_rc=$?   # deliberately UNQUOTED -- leading-dash word lands in the harness slot
case "$crt_out" in
  *'"status":"match"'*) bad "SMUGGLE (slots 1-2): a leading-dash word in the harness/tier slot injected --rollout-file -> wrong match: $crt_out" ;;
  *)
    [ "$crt_rc" -eq 2 ] && ok "shim forces EVERY positional after --: unquoted '--rollout-file X codex mid -' -> exit 2, no match" \
      || bad "slot-1-2 smuggle: expected exit 2, got $crt_rc: $crt_out" ;;
esac

# The QUOTED form is one positional -> a non-UUID thread id -> invalid / thread-id-invalid.
crt_out="$(sh "$CRT" codex mid "$_smuggle" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"invalid"'*'thread-id-invalid'*)
    [ "$crt_rc" -ne 0 ] && ok "quoted '- --rollout-file X' -> invalid / thread-id-invalid" \
      || bad "quoted smuggle exit 0" ;;
  *) bad "quoted smuggle did not report invalid / thread-id-invalid: $crt_out" ;;
esac

# CODEX_HOME sessions-dir resolution: a lowercase-UUID thread id, matched by rollout
# FILENAME only. Two matches -> ambiguous; empty sessions/ -> no rollout; no sessions/ ->
# sessions dir unavailable.
CH_UUID="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
CH_TWO="$(mktemp -d)"; mkdir -p "$CH_TWO/sessions/nested"
cp "$CRF/match/rollout.jsonl" "$CH_TWO/sessions/rollout-2026-a-$CH_UUID.jsonl"
cp "$CRF/match/rollout.jsonl" "$CH_TWO/sessions/nested/rollout-2026-b-$CH_UUID.jsonl"
crt_out="$(env CODEX_HOME="$CH_TWO" sh "$CRT" codex mid "$CH_UUID" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"invalid"'*'rollout-ambiguous'*)
    [ "$crt_rc" -ne 0 ] && ok "CODEX_HOME with two rollout-*-<uuid>.jsonl -> invalid / rollout-ambiguous, exit $crt_rc" \
      || bad "rollout-ambiguous but exit 0" ;;
  *) bad "two matching rollouts did not report invalid / rollout-ambiguous: $crt_out" ;;
esac
rm -rf "$CH_TWO"

CH_EMPTY="$(mktemp -d)"; mkdir -p "$CH_EMPTY/sessions"
crt_out="$(env CODEX_HOME="$CH_EMPTY" sh "$CRT" codex mid "$CH_UUID" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"unavailable"'*'rollout-unavailable'*)
    [ "$crt_rc" -ne 0 ] && ok "CODEX_HOME with an empty sessions/ -> unavailable / rollout-unavailable, exit $crt_rc" \
      || bad "rollout-unavailable but exit 0" ;;
  *) bad "empty sessions/ did not report unavailable / rollout-unavailable: $crt_out" ;;
esac
rm -rf "$CH_EMPTY"

CH_NOSESS="$(mktemp -d)"
crt_out="$(env CODEX_HOME="$CH_NOSESS" sh "$CRT" codex mid "$CH_UUID" 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status":"unavailable"'*'sessions-dir-unavailable'*)
    [ "$crt_rc" -ne 0 ] && ok "CODEX_HOME with no sessions/ -> unavailable / sessions-dir-unavailable, exit $crt_rc" \
      || bad "sessions-dir-unavailable but exit 0" ;;
  *) bad "missing sessions/ did not report unavailable / sessions-dir-unavailable: $crt_out" ;;
esac
rm -rf "$CH_NOSESS"

# No invocation may leak rollout free text. Every fixture carries a distinctive string in a
# non-route field; none of it may appear on stdout/stderr. Direct check-route.py calls,
# guarded on a usable interpreter.
if [ -n "$PYBIN" ]; then
  leak_out="$(
    for fx in match mismatch invalid-no-turn-context decoy-nested-model-string \
              decoy-nested-turn-context-obj decoy-nested-after-real decoy-only-nested \
              decoy-realshape-nested-after-real decoy-realshape-only-nested; do
      "$PYBIN" "$CRPY" codex mid - --rollout-file "$CRF/$fx/rollout.jsonl" 2>&1
    done
  )"
  case "$leak_out" in
    *"no turn_context record anywhere"*|*"here is the config I would use"*|*'"kind":"reasoning"'*|*"assistant said"*|*"replaying an earlier snapshot"*|*"no top-level turn_context anywhere"*|*"snapshot-replay-marker-alpha"*|*"nested-only-realshape-marker-beta"*)
      bad "check-route leaked rollout free text into its output: $leak_out" ;;
    *) ok "no invocation leaked rollout free text (only status/reason/model/effort emitted)" ;;
  esac
else
  echo "  SKIP: rollout free-text leak check (no direct python3/python 3.11+)"
fi

# EXPECTED_MODEL / EXPECTED_EFFORT gate: a malformed config/model-map.yml value (injected
# JSON) must be rejected at the tier-map trust boundary -- exit 2, NO JSON line. Stand up a
# throwaway scripts/ + config/ pair (the shim, its .py parser, and model-for.sh) and let
# the copied model-for.sh resolve against the malformed fixture map via its own
# $HERE/../config/model-map.yml.
GATEDIR="$(mktemp -d)"
mkdir -p "$GATEDIR/scripts" "$GATEDIR/config"
cp "$CRT" "$GATEDIR/scripts/check-route.sh"
cp "$CORE/scripts/check-route.py" "$GATEDIR/scripts/check-route.py"
cp "$CORE/scripts/model-for.sh" "$GATEDIR/scripts/model-for.sh"
cp "$CRF/malformed-map/model-map.yml" "$GATEDIR/config/model-map.yml"
crt_out="$(sh "$GATEDIR/scripts/check-route.sh" codex mid - 2>&1)"; crt_rc=$?
case "$crt_out" in
  *'"status"'*) bad "malformed model-map value reached a JSON status line -- must exit 2 with no JSON: $crt_out" ;;
  *)
    [ "$crt_rc" -eq 2 ] && ok "malformed model-map value -> exit 2, no JSON line" \
      || bad "malformed model-map value expected exit 2, got $crt_rc: $crt_out" ;;
esac
rm -rf "$GATEDIR"

# The shim's interpreter-skip path: with PATH stripped so neither `python3` nor `python`
# resolves, the shim prints a "route check skipped" notice to stderr and exits 3 -- a
# caller can tell "no interpreter" (3) from a real verdict (0/1) or a usage error (2).
# SKIP (not bad) if a usable interpreter cannot actually be hidden in this test env.
NOPY="$(mktemp -d)"
SH_ABS="$(command -v sh)"
np_out="$(env PATH="$NOPY" "$SH_ABS" "$CRT" codex mid - 2>&1)"; np_rc=$?
case "$np_out" in
  *'route check skipped'*)
    [ "$np_rc" -eq 3 ] && ok "shim: no python3/python 3.11+ on PATH -> 'route check skipped', exit 3" \
      || bad "shim printed the skip notice but exited $np_rc (want 3)" ;;
  *'"status"'*)
    echo "  SKIP: interpreter-hiding case (a python stayed reachable with PATH=$NOPY)" ;;
  *)
    echo "  SKIP: interpreter-hiding case (unexpected env: $np_out)" ;;
esac
rm -rf "$NOPY"

echo
echo "=== gate.sh Python pytest-config detection (Phase-4 FIX 11: fail-open guard, ported from feat/benchmark) ==="

# gate.sh's config-section branch lets an explicit pytest config force an unconditional
# `pytest -q` (only exit 5 tolerated). FIX 11 hardens three gaps:
#   (1) a repo with .py source but NO tests and NO config must still stay green;
#   (2) `[tool.pytest.ini_options]` pointing discovery at non-default filenames must catch
#       a failing test (not be skipped by the filename guard);
#   (3) tox.ini `[pytest]` is a real pytest config location and must be honored too.
if command -v pytest >/dev/null 2>&1; then
  GP="$(mktemp -d)"

  mkdir -p "$GP/nosuite"
  printf 'x = 1\n' > "$GP/nosuite/mod.py"
  expect_code 0 "a repo with .py source but no tests and no pytest config passes the gate" \
    bash -c "cd '$GP/nosuite' && bash '$CORE/scripts/gate.sh'"

  mkdir -p "$GP/pyproj"
  printf '[tool.pytest.ini_options]\npython_files = ["spec_*.py"]\n' > "$GP/pyproj/pyproject.toml"
  printf 'def test_it():\n    assert False\n' > "$GP/pyproj/spec_thing.py"
  gp_code=0
  ( cd "$GP/pyproj" && bash "$CORE/scripts/gate.sh" ) >/dev/null 2>&1 || gp_code=$?
  if [ "$gp_code" -ne 0 ]; then
    ok "[tool.pytest.ini_options] + a failing non-default-named test reddens the gate (exit $gp_code)"
  else
    bad "[tool.pytest.ini_options] failing test did NOT redden the gate (exit 0)"
  fi

  mkdir -p "$GP/toxcfg"
  printf '[pytest]\npython_files = spec_*.py\n' > "$GP/toxcfg/tox.ini"
  printf 'def test_it():\n    assert False\n' > "$GP/toxcfg/spec_thing.py"
  tx_code=0
  ( cd "$GP/toxcfg" && bash "$CORE/scripts/gate.sh" ) >/dev/null 2>&1 || tx_code=$?
  if [ "$tx_code" -ne 0 ]; then
    ok "tox.ini [pytest] + a failing non-default-named test reddens the gate (exit $tx_code)"
  else
    bad "tox.ini [pytest] failing test did NOT redden the gate (exit 0) -- config location not honored"
  fi

  rm -rf "$GP"
else
  echo "  SKIP: gate.sh pytest-config assertions (pytest not on PATH)"
fi

if [ "$fail" -ne 0 ]; then echo "test-scripts: $fail failed, $pass passed"; exit 1; fi
echo "test-scripts: OK ($pass passed)"
