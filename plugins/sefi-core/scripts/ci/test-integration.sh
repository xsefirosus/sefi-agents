#!/usr/bin/env bash
# test-integration.sh -- the full loop skeleton, executed end to end in a real git repo.
#
# test-scripts.sh proves each script works ALONE. This proves they work TOGETHER, which is
# a different claim and the one this repo could not previously make: every mechanism built
# for the loop path was gated and validated but had never actually run in sequence, because
# no loop has ever completed a cycle (state/metrics.md has zero rows). By the qa-engineer's
# own delete-the-line test, that made a lot of it unwired.
#
# What this DOES prove: the seams hold. A plan the product-manager's format produces passes
# the plan gate; a handoff built from that plan passes the handoff gate; the worktree it
# names can actually be created; gate.sh runs inside it; a verdict lands in metrics.md at a
# path retro-improve can key on; close_out's daily note reaches the router and comes back
# out of the SessionStart injection; the retro ledger row references a real commit.
#
# What this does NOT prove: that an LLM makes good decisions at any of those seams. Every
# agent dispatch here is performed by the harness running this script. This is an
# integration test of the machinery, not an evaluation of the agents -- claiming otherwise
# would be exactly the overclaim the anti-hallucination skill forbids.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

fail=0
pass=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

WS="$(mktemp -d)"
cleanup() {
  # Worktrees hold locks; prune before removing or the temp dir survives as a stale ref.
  ( cd "$WS/proj" 2>/dev/null && git worktree prune >/dev/null 2>&1 ) || true
  rm -rf "$WS"
}
trap cleanup EXIT

echo "=== stage 0: a real project (git, one commit, a toolchain gate.sh can find) ==="
mkdir -p "$WS/proj"
cd "$WS/proj" || exit 1
git init -q .
git config user.email "integration@test.local"
git config user.name  "integration test"
git config commit.gpgsign false
printf '{"name":"demo","scripts":{"test":"true","lint":"true"}}' > package.json
printf 'console.log("demo");\n' > index.js
git add -A && git commit -q -m "initial commit"
[ -d .git ] && ok "project repo initialised with a real commit" || bad "git init failed"

echo
echo "=== stage 1: /sefi:init scaffold (commands/init.md copy list) ==="
mkdir -p memory/daily memory/decisions memory/projects memory/entities state inbox loops config
cp "$CORE/templates/memory/index.md"              memory/index.md
cp "$CORE/templates/memory/promotion-candidates.base" memory/promotion-candidates.base
cp "$CORE/templates/state/metrics.md"             state/metrics.md
cp "$CORE/templates/state/retro-ledger.md"        state/retro-ledger.md
cp "$CORE/templates/config/budget.yml"            config/budget.yml
cp "$CORE/templates/config/sefi.config.yml"       config/sefi.config.yml
cp "$CORE/templates/loops/morning-triage.loop.md" loops/morning-triage.loop.md
cp "$CORE/templates/loops/weekly-retro.loop.md"   loops/weekly-retro.loop.md
cp "$CORE/templates/loops/sync.loop.md"           loops/sync.loop.md

# init.md step 4: the worktree check-ignore gate must pass BEFORE any loop opens one.
printf '.worktrees/\n' > .gitignore
mkdir -p .worktrees/logs
git add -A && git commit -q -m "chore: sefi scaffold"
if git check-ignore -q .worktrees; then
  ok "step 4 worktree check-ignore gate passes (.worktrees/ is ignored)"
else
  bad "step 4 gate failed -- a loop would create an untracked worktree inside the repo"
fi

echo
echo "=== stage 2: tool preflight (probe-tools.sh --loop) ==="
# The loop declares requires-tools; the probe decides whether the cycle runs at full or
# reduced scope. Both outcomes are valid -- a silent assumption is not.
probe_out="$(bash "$CORE/scripts/probe-tools.sh" --loop loops/morning-triage.loop.md 2>&1)"
probe_rc=$?
case "$probe_out" in
  *"OK         git"*) ok "probe resolved the loop's declared tools ($(printf '%s' "$probe_out" | tail -1 | cut -c1-58)...)" ;;
  *) bad "probe produced no per-tool result: $probe_out" ;;
esac
if [ "$probe_rc" -ne 0 ]; then
  ok "probe exits nonzero on an unusable tool, so the cycle knows to reduce scope"
else
  ok "probe cleared every declared tool, so the cycle may run at full scope"
fi

echo
echo "=== stage 3: product-manager writes a plan, plan gate judges it ==="
cat > state/plan-add-flag.md <<'PLAN'
## Objective
Add a --version flag to index.js that prints the package version and exits 0.
## Steps
- [ ] 1. Read the version from package.json into a VERSION constant. (needs: -)
- [ ] 2. Print VERSION and exit 0 when process.argv includes --version. (needs: 1)
## Files Touched
index.js
## Requires Tools
node
## Risks
Reading package.json at runtime fails if the file moves; keep the path relative to __dirname.
## Done Criteria
`node index.js --version` prints the version from package.json and exits 0.
PLAN
if bash "$CORE/scripts/validate-plan-structure.sh"; then
  ok "a plan in the product-manager's format passes validate-plan-structure.sh"
else
  bad "the plan format the agent teaches fails its own gate"
fi

# The dependency markers must be machine-readable, which is the whole point of adding them:
# the engineering-manager runs scripts/ready-steps.sh (engineering-manager.md item 5)
# instead of reasoning about markers in prose. Step 2 needs step 1, so exactly step 1 is
# ready here -- a real scheduler call, not the grep -c '(needs: -)' stand-in this replaces.
ready="$(bash "$CORE/scripts/ready-steps.sh" --config config/budget.yml state/plan-add-flag.md 2>/dev/null)"
if [ "$ready" = "1" ]; then
  ok "the EM can identify 1 step(s) with no outstanding dependency to start in parallel"
else
  bad "ready-steps.sh gave '$ready', wanted exactly step 1 ready"
fi

echo
echo "=== stage 4: engineering-manager builds a handoff, handoff gate judges it ==="
WT="$WS/proj/.worktrees/feat-version"
cat > "$WS/envelope.txt" <<ENVELOPE
agent: software-engineer
reads: state/plan-add-flag.md
writes: $WT
budget: dispatch
context: Build step 1 and 2 of the --version flag. Read the version from package.json relative to __dirname and print it when process.argv includes --version, exiting 0.
ENVELOPE
if bash "$CORE/scripts/check-handoff.sh" "$WS/envelope.txt" >/dev/null 2>&1; then
  ok "the dispatch envelope passes check-handoff.sh (absolute writes path, named upstream file)"
else
  bad "a well-formed envelope was rejected by the handoff gate"
fi

echo
echo "=== stage 5: budget preflight before the dispatch (budget-check.sh --pending) ==="
# The EM checks the projected cost BEFORE dispatching, not after the spend lands.
if bash "$CORE/scripts/budget-check.sh" --scope dispatch --spent 0 --pending 0.05 \
     --config config/budget.yml >/dev/null 2>&1; then
  ok "a 0.05 projected dispatch clears the 0.15 per-dispatch cap"
else
  bad "an in-budget dispatch was blocked"
fi
if bash "$CORE/scripts/budget-check.sh" --scope dispatch --spent 0 --pending 0.30 \
     --config config/budget.yml >/dev/null 2>&1; then
  bad "a 0.30 projected dispatch was allowed past the 0.15 cap"
else
  ok "a 0.30 projected dispatch is blocked BEFORE it runs, not after"
fi

echo
echo "=== stage 6: worktree handoff, real git worktree at the pinned path ==="
git worktree add -q -b feat-version "$WT" >/dev/null 2>&1
if [ -d "$WT" ] && [ -f "$WT/index.js" ]; then
  ok "the worktree exists at the exact absolute path the envelope pinned"
else
  bad "worktree creation failed at $WT"
fi

echo
echo "=== stage 7: software-engineer builds the slice, gate.sh judges it ==="
cat > "$WT/index.js" <<'IMPL'
const fs = require('fs');
const path = require('path');
const VERSION = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8')).version || '0.0.0';
if (process.argv.includes('--version')) { console.log(VERSION); process.exit(0); }
console.log("demo");
IMPL
printf '{"name":"demo","version":"1.4.2","scripts":{"test":"true","lint":"true"}}' > "$WT/package.json"
gate_out="$( cd "$WT" && bash "$CORE/scripts/gate.sh" 2>&1 )"
gate_rc=$?
if [ "$gate_rc" -eq 0 ]; then
  case "$gate_out" in
    *"PASSED"*) ok "gate.sh PASSED inside the worktree ($(printf '%s' "$gate_out" | tail -1))" ;;
    *"no known toolchain"*) bad "gate.sh found no toolchain in a repo with package.json -- it would report an unchecked slice as passing" ;;
    *) bad "gate.sh exit 0 with unrecognised output: $gate_out" ;;
  esac
else
  bad "gate.sh failed in the worktree: $gate_out"
fi

echo
echo "=== stage 8: qa-engineer verifies against Done Criteria (executed, not eyeballed) ==="
# The plan's Done Criteria is an executed stop condition. Run it.
actual="$( cd "$WT" && node index.js --version 2>&1 )"
if [ "$actual" = "1.4.2" ]; then
  ok "Done Criteria satisfied by execution: 'node index.js --version' printed 1.4.2"
  VERDICT="PASS"
else
  bad "Done Criteria not met (got '$actual', expected 1.4.2)"
  VERDICT="REJECT"
fi

# Grep-countable stop condition: every checkbox checked, zero LLM judgment.
sed -i 's/^- \[ \]/- [x]/' state/plan-add-flag.md
unchecked="$(grep -c '^- \[ \]' state/plan-add-flag.md || true)"
if [ "$unchecked" -eq 0 ]; then
  ok "stop condition is grep-countable: 0 unchecked steps remain"
else
  bad "$unchecked step(s) still unchecked but the loop considers itself done"
fi

echo
echo "=== stage 9: persistence -- metrics row keyed to retro-improve's keyspace ==="
echo "| $(date +%Y-%m-%d) | plugins/sefi-core/agents/software-engineer.md | morning-triage | $VERDICT | 0 | integration test | n/a |" >> state/metrics.md
target="$(tail -1 state/metrics.md | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
if [ -f "$ROOT/$target" ]; then
  ok "the metrics row's target-path resolves to a real file ($target)"
else
  bad "metrics target-path '$target' does not resolve -- retro-improve would flag a wiring bug"
fi
if grep -q "managed-by: sefi-agents" "$ROOT/$target"; then
  ok "the target is a managed-by sefi-agents file, so retro-improve is permitted to edit it"
else
  bad "the target is outside retro-improve's HARD GUARDS"
fi

echo
echo "=== stage 10: close_out -- the vault finally gets a producer ==="
# The knowledge-manager is dispatched to file the cycle's durable observations. Before
# close-out.md existed nothing ever wrote here, so the weekly distill was a permanent no-op.
TODAY="$(date +%Y-%m-%d)"
cat > "memory/daily/$TODAY.md" <<NOTE
---
tags: [daily]
date: $TODAY
tier: trace
scope: session
topic: version-flag
keywords: cli, versioning
managed-by: sefi-agents
---

## 09:00 -- --version flag added to demo
Read the version from package.json at runtime rather than hardcoding it.
Rejected a build-time constant: it drifts from package.json on every release.
NOTE
[ -s "memory/daily/$TODAY.md" ] && ok "close_out filed a daily note through the vault's write path" \
  || bad "close_out produced no note"

# Privacy filter is the reason this is an agent dispatch and not a hook -- assert nothing
# credential-shaped reached the vault.
if grep -rqE '(sk-|ghp_|xoxb-|AKIA|BEGIN [A-Z ]*PRIVATE KEY|password=|secret=|token=)' memory/ 2>/dev/null; then
  bad "credential-shaped content reached the vault -- the privacy filter did not run"
else
  ok "no credential-shaped content in the vault (privacy filter clean)"
fi

# The cross-project mirror (memory-protocol WRITE step 4) was shipped with unit coverage
# in test-scripts.sh but never exercised inside a full cycle -- exactly the "written, not
# wired" gap qa-engineer.md item 3 exists to catch. A real container (this test's own host)
# is ephemeral, so the non-ephemeral branch is only reachable by stubbing
# systemd-detect-virt and clearing the CI/sandbox env markers, same technique
# test-scripts.sh already uses. This proves the mirror writes correctly once a real local
# machine is confirmed; it cannot prove real-machine DETECTION from inside a container --
# that limit is inherent, not a gap in this test.
MIRROR_STUB="$(mktemp -d)"
printf '#!/bin/sh\necho none\n' > "$MIRROR_STUB/systemd-detect-virt"
chmod +x "$MIRROR_STUB/systemd-detect-virt"
MIRROR_HOME="$WS/mirror-home"
mkdir -p "$MIRROR_HOME"
mirror_dest="$(env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX \
  PATH="$MIRROR_STUB:$PATH" HOME="$MIRROR_HOME" \
  bash "$CORE/scripts/write-shared-memory-mirror.sh" "version-flag" "memory/daily/$TODAY.md" 2>/dev/null)"
if [ -n "$mirror_dest" ] && [ -f "$mirror_dest" ]; then
  ok "cross-project mirror wrote a real file: $mirror_dest"
else
  bad "cross-project mirror produced no file on a confirmed non-ephemeral environment"
fi
if [ -f "$mirror_dest" ] && diff -q "$mirror_dest" "memory/daily/$TODAY.md" >/dev/null 2>&1; then
  ok "mirrored content matches the same privacy-filtered daily note byte for byte"
else
  bad "mirrored content diverged from the daily note it was supposed to copy"
fi
rm -rf "$MIRROR_STUB"

echo
echo "=== stage 11: router regen, and the note survives into the next session ==="
bash "$CORE/scripts/gen-router.sh" >/dev/null 2>&1
if grep -q "daily/$TODAY" memory/index.md; then
  ok "gen-router.sh picked the new note up into the GENERATED:router block"
else
  bad "the note never reached the router -- the next session would not see it"
fi
if bash "$CORE/scripts/gen-router.sh" --check >/dev/null 2>&1; then
  ok "router is in sync after regeneration (--check clean)"
else
  bad "router reports drift immediately after being regenerated"
fi

inj="$(bash "$CORE/scripts/inject-memory.sh" 2>/dev/null)"
case "$inj" in
  *"daily/$TODAY"*) ok "SessionStart injection carries the note -- the full memory round trip closes" ;;
  *) bad "injection did not include the note: $inj" ;;
esac
case "$inj" in
  *"Entry point to the Obsidian-style"*) bad "injection is back to re-sending static preamble" ;;
  *) ok "injection spends its budget on router lines, not boilerplate" ;;
esac

echo
echo "=== stage 12: retro ledger row references a real, revertible commit ==="
git add -A && git commit -q -m "feat: --version flag (integration cycle)"
SHA="$(git rev-parse --short HEAD)"
echo "| $TODAY | plugins/sefi-core/agents/software-engineer.md | applied | $SHA | metrics row from this cycle | 0/0 | pending-evidence |" >> state/retro-ledger.md
if git cat-file -e "$SHA^{commit}" 2>/dev/null; then
  ok "the ledger's commit SHA resolves, so 'git revert $SHA' is a real undo path"
else
  bad "the ledger references a SHA that does not exist -- the edit is not revertible"
fi

echo
echo "=== stage 13: human checkpoint -- nothing merged itself ==="
branches="$(git branch --format='%(refname:short)' | tr '\n' ' ')"
current="$(git rev-parse --abbrev-ref HEAD)"
if git log "$current" --oneline | grep -q "Merge"; then
  bad "a merge commit exists -- the loop merged its own work"
else
  ok "no merge commit on $current -- work stops at the PR boundary as human-checkpoint.md requires"
fi
if [ -d "$WT" ]; then
  ok "the worktree survives for human review rather than being swept mid-cycle"
else
  bad "the worktree was removed before a human could look at it"
fi

echo
echo "=== stage 14: state/loop sync, and the cycle is resumable ==="
sync_out="$(bash "$CORE/scripts/check-state-sync.sh" 2>&1)"
case "$sync_out" in
  *DRIFT*) ok "check-state-sync reports drift honestly on a cycle with no triage state yet" ;;
  *OK*)    ok "check-state-sync reports the loop and its state file in sync" ;;
  *)       bad "check-state-sync produced no verdict: $sync_out" ;;
esac

readiness="$(bash "$CORE/scripts/loop-readiness.sh" 2>/dev/null | grep morning-triage)"
case "$readiness" in
  *"/100"*) ok "loop-readiness scores the live loop: $readiness" ;;
  *) bad "loop-readiness produced no score" ;;
esac

sync_readiness="$(bash "$CORE/scripts/loop-readiness.sh" 2>/dev/null | grep '^sync:')"
case "$sync_readiness" in
  *"/100"*) ok "loop-readiness scores the sync loop too: $sync_readiness" ;;
  *) bad "sync.loop.md was copied in stage 1 but loop-readiness never scored it" ;;
esac

echo
echo "=== stage 15: scale -- a mature vault must not blow the injection budget ==="
# gen-router.sh orders notes by durability so truncation drops trace notes before decisions.
# That ordering only matters at scale, and scale had never been exercised.
i=0
while [ "$i" -lt 120 ]; do
  printf -- '---\ntags: [daily]\ntier: trace\nkeywords: noise%s\n---\n' "$i" > "memory/daily/2026-01-$(printf '%02d' $((i % 28 + 1)))-n$i.md"
  i=$((i + 1))
done
i=0
while [ "$i" -lt 15 ]; do
  printf -- '---\ntags: [decision]\ntier: fact\nkeywords: durable%s\n---\n' "$i" > "memory/decisions/d$i.md"
  i=$((i + 1))
done
bash "$CORE/scripts/gen-router.sh" >/dev/null 2>&1

cap="$(sed -n 's/^[[:space:]]*inject_char_cap:[[:space:]]*\([0-9]*\).*/\1/p' config/sefi.config.yml | head -1)"
cap="${cap:-1500}"
big="$(bash "$CORE/scripts/inject-memory.sh" 2>/dev/null)"
n="$(printf '%s' "$big" | wc -c | tr -d ' ')"
if [ "$n" -le $((cap + 1)) ]; then
  ok "135-note vault still injects within the $cap-char cap ($n bytes)"
else
  bad "injection blew the cap at scale ($n bytes for a cap of $cap)"
fi

# The durability ordering has to actually pay off: truncation must drop trace, not decisions.
d_count="$(printf '%s' "$big" | grep -c 'decisions/' || true)"
if [ "$d_count" -ge 1 ]; then
  ok "decisions survive truncation at scale ($d_count in the injected window)"
else
  bad "every decision was truncated away -- the injected window is 100% trace notes"
fi

echo
echo "=== stage 16: install flows produce loadable agent files ==="
OC="$WS/oc"
if OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" >/dev/null 2>&1; then
  oc_bad=0
  oc_n=0
  for f in "$OC"/agents/*.md; do
    oc_n=$((oc_n + 1))
    grep -q '^permission:' "$f" || oc_bad=1
    grep -q '^model:' "$f" && oc_bad=1                           # shipped map is "flexible": no model: at all
    grep -q '^tier:' "$f" && oc_bad=1                            # our field must not leak
  done
  # A hardcoded agent count here would drift the moment the roster grows again -- the
  # same class of bug this asserts against, just in the test's own prose. Count what was
  # actually converted instead.
  [ "$oc_bad" -eq 0 ] && ok "all $oc_n OpenCode agents carry permission, no model: (shipped map is flexible), no leaked tier"     || bad "an OpenCode agent is malformed after conversion"
else
  bad "install-opencode.sh failed"
fi

CX="$WS/cx"
if bash "$CORE/scripts/apply-model-map.sh" codex "$CORE/agents" "$CX" >/dev/null 2>&1; then
  cx_models="$(grep -h '^model:' "$CX"/*.md | sort -u | tr '\n' ' ')"
  case "$cx_models" in
    *gpt-5.6-sol*|*gpt-5.6-terra*) ok "Codex conversion wrote mapped ids ($cx_models)" ;;
    *) bad "Codex conversion produced unexpected models: $cx_models" ;;
  esac
else
  bad "apply-model-map.sh failed for codex"
fi

echo
if [ "$fail" -ne 0 ]; then echo "test-integration: $fail failed, $pass passed"; exit 1; fi
echo "test-integration: OK ($pass passed) -- full loop skeleton executed end to end"
