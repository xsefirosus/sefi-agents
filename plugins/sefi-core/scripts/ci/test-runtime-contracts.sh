#!/usr/bin/env bash
# Focused, isolated regression checks for runtime trust-boundary contracts.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
S="$CORE/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }
expect() {
  local want="$1" label="$2" got=0
  shift 2
  "$@" >/dev/null 2>&1 || got=$?
  [ "$got" -eq "$want" ] && ok "$label" || bad "$label (wanted $want, got $got)"
}

# Handoff envelopes are a single, complete and unambiguous authority record.
good_envelope() {
  printf '%s\n' 'agent: software-engineer' 'reads: state/plan.md' \
    "writes: $TMP/out" 'budget: dispatch' 'context: Build the named slice.'
}
good_envelope > "$TMP/good-envelope.txt"
expect 0 'valid handoff remains accepted' bash "$S/check-handoff.sh" "$TMP/good-envelope.txt"
good_envelope | sed 's/^agent:.*/agent: /' | bash "$S/check-handoff.sh" - >/dev/null 2>&1 && bad 'empty agent is rejected' || ok 'empty agent is rejected'
good_envelope | sed '/^context:/i budget: daily' | bash "$S/check-handoff.sh" - >/dev/null 2>&1 && bad 'duplicate handoff fields are rejected' || ok 'duplicate handoff fields are rejected'
good_envelope | sed 's/^budget:.*/budget: nonsense value/' | bash "$S/check-handoff.sh" - >/dev/null 2>&1 && bad 'unsafe budget is rejected' || ok 'unsafe budget is rejected'
good_envelope | sed 's#^writes:.*#writes: C:\\approved\\..\\outside#' | bash "$S/check-handoff.sh" - >/dev/null 2>&1 && bad 'Windows traversal is rejected' || ok 'Windows traversal is rejected'

cat > "$TMP/budget.yml" <<'EOF'
max_parallel_worktrees: 3
EOF
cat > "$TMP/duplicate-steps.md" <<'EOF'
## Steps
- [x] 1. done (needs: -)
- [ ] 1. duplicate (needs: -)
EOF
expect 1 'duplicate step ids are malformed' bash "$S/ready-steps.sh" --config "$TMP/budget.yml" "$TMP/duplicate-steps.md"
cat > "$TMP/bad-step.md" <<'EOF'
## Steps
- [ ] 0. zero (needs: -)
EOF
expect 1 'nonpositive step ids are malformed' bash "$S/ready-steps.sh" --config "$TMP/budget.yml" "$TMP/bad-step.md"
cat > "$TMP/bad-dependency.md" <<'EOF'
## Steps
- [ ] 1. first (needs: 1,abc)
EOF
expect 1 'invalid dependency syntax is malformed' bash "$S/ready-steps.sh" --config "$TMP/budget.yml" "$TMP/bad-dependency.md"
expect 2 'missing --config value is a bounded usage error' timeout 2 bash "$S/ready-steps.sh" --config

mkdir -p "$TMP/state"
cat > "$TMP/state/plan-empty.md" <<'EOF'
## Objective

## Steps
- [ ] 1. first (needs: -)
## Files Touched
none
## Requires Tools
none
## Risks
none
## Done Criteria
done
EOF
expect 1 'empty required plan section is rejected' bash -c "cd '$TMP' && bash '$S/validate-plan-structure.sh' --file state/plan-empty.md"
cat > "$TMP/state/plan-duplicate.md" <<'EOF'
## Objective
ship it
## Steps
- [ ] 1. first (needs: -)
- [ ] 1. duplicate (needs: -)
## Files Touched
none
## Requires Tools
none
## Risks
none
## Done Criteria
done
EOF
expect 1 'duplicate plan steps are rejected by the structural validator' bash -c "cd '$TMP' && bash '$S/validate-plan-structure.sh' --file state/plan-duplicate.md"

mkdir -p "$TMP/with space"
printf 'one\ntwo' > "$TMP/with space/cited file.txt"
printf 'verified against %s:0\n' "$TMP/with space/cited file.txt" | bash "$S/check-citation.sh" - >/dev/null 2>&1 && bad 'citation line zero is rejected' || ok 'citation line zero is rejected'
printf 'verified against README.md:1\n' | bash "$S/check-citation.sh" - >/dev/null 2>&1 && ok 'repository citation remains accepted' || bad 'repository citation is rejected'
printf 'verified against %s:2\n' "$TMP/with space/cited file.txt" | bash "$S/check-citation.sh" - >/dev/null 2>&1 && bad 'external citation path is rejected' || ok 'external citation path is rejected'
ln -s "$ROOT/README.md" "$TMP/citation-link.md" 2>/dev/null || true
if [ -L "$TMP/citation-link.md" ]; then
  printf 'verified against %s:1\n' "$TMP/citation-link.md" | bash "$S/check-citation.sh" - >/dev/null 2>&1 && bad 'symlink citation path is rejected' || ok 'symlink citation path is rejected'
else
  printf 'SKIP: citation symlink test unavailable on this host\n'
fi

cat > "$TMP/route.jsonl" <<'EOF'
{"type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"high"}}
{"type":"turn_context","payload":null}
EOF
PYBIN=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys; raise SystemExit(sys.version_info >= (3, 11))' >/dev/null 2>&1; then PYBIN="$p"; break; fi
done
if [ -n "$PYBIN" ]; then
  route_out="$($PYBIN "$S/check-route.py" codex mid - --rollout-file "$TMP/route.jsonl" 2>&1)"; route_rc=$?
  case "$route_out" in *'"status":"invalid"'*'turn-context-malformed'*) [ "$route_rc" -eq 1 ] && ok 'malformed latest route evidence cannot fall back' || bad 'malformed latest route uses the wrong exit' ;; *) bad "malformed latest route was accepted: $route_out" ;; esac
else
  printf 'SKIP: Python 3.11 unavailable\n'
fi

cat > "$TMP/caps.yml" <<'EOF'
per_run_usd_cap: 1.00
daily_usd_cap: 2.00
per_dispatch_usd_cap: 0.15
EOF
expect 2 'unknown budget scope is rejected' bash "$S/budget-check.sh" --scope unknown --spent 0 --config "$TMP/caps.yml"
expect 2 'missing budget value is a usage error' bash "$S/budget-check.sh" --spent

mkdir -p "$TMP/empty-gate"
expect 1 'strict gate cannot pass without a verification' bash -c "cd '$TMP/empty-gate' && bash '$S/gate.sh' --strict"

mkdir -p "$TMP/compress"
( cd "$TMP/compress" && bash "$S/compress-output.sh" same true && bash "$S/compress-output.sh" same true ) >/dev/null
logs="$(find "$TMP/compress/.worktrees/logs" -type f | wc -l | tr -d ' ')"
[ "$logs" -eq 2 ] && ok 'compressor uses collision-free log names' || bad "compressor log collision (found $logs files)"

mkdir -p "$TMP/readiness/loops" "$TMP/readiness/state"
cat > "$TMP/readiness/loops/demo.loop.md" <<'EOF'
## Trigger
## Discovery
## Handoff
## Verification
## Persistence
goal_intake refusal_gate verification loop_discipline close_out
## Human checkpoint
## Budget
$1
EOF
printf 'the word demo appears here but this is not a metrics row\n' > "$TMP/readiness/state/metrics.md"
readiness="$(cd "$TMP/readiness" && bash "$S/loop-readiness.sh" 2>/dev/null)"
case "$readiness" in 'demo: 80/100 (L3 Proven)') bad 'plain metrics mention cannot establish proven readiness' ;; 'demo: 80/100 (L3 Proven)'*) bad 'plain metrics mention cannot establish proven readiness' ;; *'demo: 80/100'*) ok 'plain metrics mention does not establish proof' ;; *) ok 'plain metrics mention does not establish proof' ;; esac

if [ "$fail" -ne 0 ]; then printf 'test-runtime-contracts: %s failed, %s passed\n' "$fail" "$pass"; exit 1; fi
printf 'test-runtime-contracts: OK (%s passed)\n' "$pass"
