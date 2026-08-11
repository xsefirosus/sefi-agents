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
echo "=== install-opencode.sh (live bug, 2026-07-19: OpenCode hard-fails resolving a Claude Code model alias) ==="

# Live-observed: model: sonnet (a Claude Code tier alias) made OpenCode's own subagent
# dispatch fail hard with "Model not found: sonnet/" -- OpenCode tries to resolve the
# value as a real provider/model identifier and does not silently ignore it the way
# Claude Code treats "sonnet" as a native alias. Every one of this repo's 13 agents
# carries a model: line, so this broke every subagent dispatch on OpenCode, not one.
TMP_OC="$(mktemp -d)"
OPENCODE_HOME="$TMP_OC" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1

# The original guard, unchanged in intent: no bare Claude Code tier alias may survive into
# an OpenCode agent file, because OpenCode resolves the value as a real provider/model id
# and fails hard on "sonnet". v0.2.3 satisfies this by REPLACING the alias via
# config/model-map.yml rather than deleting the field -- deleting it fixed the crash but
# made every agent inherit one session model, so the qa-engineer judged the
# software-engineer on the identical model and generator/evaluator separation went with it.
oc_model="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC/agents/software-engineer.md" 2>/dev/null | head -1)"
case "$oc_model" in
  opus|sonnet|haiku)
    bad "a bare Claude Code alias ('$oc_model') survived into the OpenCode agent file" ;;
  "")
    bad "install-opencode.sh emitted no model: at all (every agent falls back to one session model)" ;;
  *)
    ok "install-opencode.sh emits a mapped OpenCode model ('$oc_model'), not a Claude alias" ;;
esac

# The tier is this repo's own field and must not leak into a harness file.
if grep -q '^tier:' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  bad "tier: leaked into the converted OpenCode agent file"
else
  ok "install-opencode.sh consumes tier: without leaking it"
fi

# Tier differentiation must actually work: with a map that gives distinct models per tier,
# the high-tier judge and the mid-tier generator must NOT resolve to the same model.
OC_MAP="$(mktemp)"
printf 'opencode:\n  high: judge-model\n  mid: build-model\n  low: cheap-model\n' > "$OC_MAP"
TMP_OC2="$(mktemp -d)"
OPENCODE_HOME="$TMP_OC2" bash "$CORE/scripts/install-opencode.sh" --model-map "$OC_MAP" >/dev/null 2>&1
qa_m="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC2/agents/qa-engineer.md" 2>/dev/null | head -1)"
se_m="$(sed -n 's/^model:[[:space:]]*//p' "$TMP_OC2/agents/software-engineer.md" 2>/dev/null | head -1)"
if [ "$qa_m" = "judge-model" ] && [ "$se_m" = "build-model" ]; then
  ok "tiers differentiate on OpenCode (qa=$qa_m vs engineer=$se_m), restoring generator/evaluator separation"
else
  bad "tier differentiation broken on OpenCode (qa='$qa_m' engineer='$se_m')"
fi
rm -rf "$TMP_OC2" "$OC_MAP"
# Everything else must still survive byte-for-byte: pick one field per source line kind.
if grep -q '^disallowedTools: WebFetch, WebSearch$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null \
   && grep -q '^  edit: allow$' "$TMP_OC/agents/software-engineer.md" 2>/dev/null; then
  ok "install-opencode.sh still converts tools/permission and keeps other fields intact"
else
  bad "install-opencode.sh regressed the tools/permission conversion or another frontmatter field"
fi
rm -rf "$TMP_OC"

echo
if [ "$fail" -ne 0 ]; then echo "test-scripts: $fail failed, $pass passed"; exit 1; fi
echo "test-scripts: OK ($pass passed)"
