#!/usr/bin/env bash
# CI: check-handoff.sh validates an optional output_schema field (Stage 2).
#
# check-handoff.sh had no dedicated suite at all before this one, which is why the
# output_schema gate needed its own: the gate's whole value is refusing a schema
# that cannot be read, and an unreadable schema is indistinguishable from a
# passing one unless something asserts on the exact rejection.
#
# The field is OPTIONAL, so the first case matters as much as the rest: an
# envelope without output_schema must keep behaving exactly as it did before.
#
# Cases run on POSIX hosts too. Schema paths are converted with sefi_native_path
# rather than a raw cygpath for the same reason the rollout fixtures were fixed:
# cygpath is absent off MSYS, and a bare call left the variable empty (live Linux
# CI failure, run 37203696158).
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$CORE/scripts/sefi-native-path.sh"

CH="$CORE/scripts/check-handoff.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# check-handoff.sh compares the writes: value against absolute-path patterns and
# reads the schema with a native tool, so both must be in native form on MSYS.
TN="$(sefi_native_path "$TMP")"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

run() { # <envelope> -> sets RC and OUT
  OUT="$(bash "$CH" "$1" 2>&1)"; RC=$?
}
# expect <desc> <want_rc> <envelope>
expect() {
  local desc="$1" want="$2" env_file="$3"
  run "$env_file"
  if [ "$RC" -eq "$want" ]; then ok "$desc (exit $RC)"
  else bad "$desc -- wanted exit $want, got $RC: $OUT"; fi
}

printf '{"required":["VERDICT:","FINDINGS:"]}\n' > "$TMP/good.json"
printf '{"type":"object"}\n'                      > "$TMP/norequired.json"
printf 'not json at all\n'                         > "$TMP/bad.json"

# The shared preamble: a minimal envelope that already satisfies every pre-existing
# check, so each case below isolates the output_schema rule and nothing else.
preamble() {
  printf 'agent: qa-engineer\nreads: /tmp/upstream.md\nwrites: %s/out.md\nbudget: run\n' "$TN"
}
envelope() { # <extra-lines...>
  { preamble; printf '%s' "$1"; printf 'context: do the thing\n'; } > "$2"
}

echo "=== check-handoff.sh output_schema gate ==="

# 1. Absent field: unchanged pre-existing behavior. If this breaks, the gate is not
#    optional in practice.
envelope "" "$TMP/e-none.txt"
expect "no output_schema field is accepted (the field is optional)" 0 "$TMP/e-none.txt"

# 2. Valid schema naming required labels: accepted.
envelope "output_schema: $TN/good.json
" "$TMP/e-good.txt"
expect "a valid schema with required labels is accepted" 0 "$TMP/e-good.txt"

# 3. Missing file. This is the case the gate exists for: a schema that cannot be
#    read fails open at return time, so it reads as "structured output is checked"
#    while nothing is checked.
envelope "output_schema: $TN/nope.json
" "$TMP/e-missing.txt"
expect "a schema path that does not exist is rejected" 1 "$TMP/e-missing.txt"

# 4. Unparseable JSON.
envelope "output_schema: $TN/bad.json
" "$TMP/e-badjson.txt"
expect "a schema that is not valid JSON is rejected" 1 "$TMP/e-badjson.txt"

# 5. Valid JSON, no required labels. Constrains nothing, so the dispatch reads as
#    structured while enforcing nothing -- the silent pass worth refusing.
envelope "output_schema: $TN/norequired.json
" "$TMP/e-noreq.txt"
expect "a schema declaring no required labels is rejected" 1 "$TMP/e-noreq.txt"

# 6. Relative schema path: same reasoning as writes: -- it would resolve against the
#    dispatched agent's inherited working directory.
{ printf 'agent: qa-engineer\nreads: /tmp/upstream.md\nwrites: %s/out.md\nbudget: run\n' "$TN"
  printf 'output_schema: relative.json\ncontext: do the thing\n'; } > "$TMP/e-rel.txt"
expect "a relative schema path is rejected" 1 "$TMP/e-rel.txt"

# 7. The rejections must explain themselves. A gate that blocks a dispatch without
#    naming the defect costs the same debugging time as no gate.
for case_file in "$TMP/e-missing.txt" "$TMP/e-badjson.txt" "$TMP/e-noreq.txt" "$TMP/e-rel.txt"; do
  run "$case_file"
  if grep -q "ERROR:" <<<"$OUT"; then ok "$(basename "$case_file") rejection names the defect"
  else bad "$(basename "$case_file") rejection gave no ERROR line: $OUT"; fi
done

# 8. Exit 2 on usage error is preserved, not swallowed by the new branch.
OUT="$(bash "$CH" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "no argument still exits 2 (usage error)" \
                || bad "no argument exited $RC, wanted 2: $OUT"

# 9. The dispatch promise is kept at return time: the schema accepted above is
#    enforced by check-reply.sh --schema, so a promised-VERDICT reply carrying
#    only prose fails there. Without this section the dispatch gate's "validated
#    against it by check-reply.sh at return time" would be an unenforced promise
#    (the fail-open this closes). Uses this suite's own good.json fixture so the
#    dispatch and return halves pin the same required labels.
CR="$CORE/scripts/check-reply.sh"
BUDGET_TPL_FIX="$CORE/templates/config/budget.yml"
printf 'VERDICT: PASS\nFINDINGS: green, see evidence\n' > "$TMP/r-good.txt"
printf 'Some thoughtful prose with no VERDICT section at all.\n' > "$TMP/r-prose.txt"
OUT="$(bash "$CR" --config "$BUDGET_TPL_FIX" --schema "$TN/good.json" "$CORE/agents/qa-engineer.md" "$TMP/r-good.txt" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "a schema-conformant reply passes return-time validation (exit 0)" \
                || bad "a schema-conformant reply was rejected at return time (exit $RC): $OUT"
OUT="$(bash "$CR" --config "$BUDGET_TPL_FIX" --schema "$TN/good.json" "$CORE/agents/qa-engineer.md" "$TMP/r-prose.txt" 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q "missing required label 'VERDICT:'" <<<"$OUT"; then
  ok "a promised-VERDICT reply carrying only prose fails return-time validation (exit 1, names VERDICT:)"
else
  bad "a promised-VERDICT prose reply did not fail closed (exit $RC): $OUT"
fi

echo
echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ] || exit 1
exit 0