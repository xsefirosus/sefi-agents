#!/usr/bin/env bash
# test-validate-skill-doc-refs.sh -- the install-context validator must accept a reference
# that resolves inside its own skill, reject one that dangles there, and exempt the
# `repo:`-prefixed form that names a repository-only path on purpose.
#
# Each case builds a throwaway tree with the same layout the validator resolves from
# (plugins/sefi-core/scripts/ci + plugins/sefi-core/skills), so the validator's own path
# resolution is exercised too -- no --root flag exists to hide a resolution bug behind.
set -uo pipefail

CORE="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$CORE/scripts/ci/validate-skill-doc-refs.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

echo "=== validate-skill-doc-refs.sh (install-context doc pointers) ==="

[ -f "$VALIDATOR" ] || { bad "validator missing at $VALIDATOR"; echo "  (0 passed, 1 failed)"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugins/sefi-core/scripts/ci" "$TMP/plugins/sefi-core/skills/demo/references"
cp "$VALIDATOR" "$TMP/plugins/sefi-core/scripts/ci/validate-skill-doc-refs.sh"
SKILL="$TMP/plugins/sefi-core/skills/demo/SKILL.md"
printf '# demo\n\nSelf reference: `references/notes.md`.\n' > "$TMP/plugins/sefi-core/skills/demo/references/notes.md"

run_case() {
  # run_case <label> <expected-exit> <skill-md-body>
  local label="$1" want="$2" body="$3" got=0 out=""
  printf '%s\n' "$body" > "$SKILL"
  out="$(bash "$TMP/plugins/sefi-core/scripts/ci/validate-skill-doc-refs.sh" 2>&1)" || got=$?
  if [ "$got" -eq "$want" ]; then
    ok "$label (exit $got)"
  else
    bad "$label (expected exit $want, got $got): $out"
  fi
  LAST_OUT="$out"
}

# A reference that resolves inside the skill directory is the normal, accepted shape.
run_case "a reference resolving inside the skill directory is accepted" 0 \
  'Read `references/notes.md` before starting.'

# The shipped defect: a bare docs/ pointer is dangling in every installed bundle.
run_case "a dangling docs/ pointer is rejected" 1 \
  'See `docs/BUDGET.md` for the spend stack.'
case "$LAST_OUT" in
  *"docs/BUDGET.md"*) ok "the rejection names the dangling path" ;;
  *) bad "the rejection did not name the dangling path: $LAST_OUT" ;;
esac
case "$LAST_OUT" in
  *repo:*) ok "the rejection names the 'repo:' remedy" ;;
  *) bad "the rejection did not name the 'repo:' remedy: $LAST_OUT" ;;
esac

# The escape hatch: explicitly repository-only references are exempt.
run_case "a repo:-prefixed reference is exempt" 0 \
  'See `repo:docs/BUDGET.md` for the spend stack.'

# A cross-skill pointer is another skill's file, not this one's: never matched.
run_case "a cross-skill skills/<name>/references path is not treated as this skill's own" 0 \
  'The rule lives in `skills/sefi-orchestration/references/human-checkpoint.md`.'

# Containment: a reference that climbs out of the skill directory is refused even when the
# target happens to exist, because that is exactly the shape this validator exists to stop.
mkdir -p "$TMP/plugins/sefi-core/docs"
printf 'x\n' > "$TMP/plugins/sefi-core/docs/ESCAPE.md"
run_case "a reference escaping the skill directory is rejected" 1 \
  'See `docs/../docs/ESCAPE.md` for the spend stack.'

# A skill with no SKILL.md is unwired, not silently skipped.
rm -f "$SKILL"
mkdir -p "$TMP/plugins/sefi-core/skills/empty"
got=0
out="$(bash "$TMP/plugins/sefi-core/scripts/ci/validate-skill-doc-refs.sh" 2>&1)" || got=$?
if [ "$got" -ne 0 ]; then ok "a skill directory with no SKILL.md is reported (exit $got)"
else bad "a skill directory with no SKILL.md passed silently: $out"; fi

echo
if [ "$fail" -ne 0 ]; then echo "test-validate-skill-doc-refs: $fail failed, $pass passed"; exit 1; fi
echo "test-validate-skill-doc-refs: OK ($pass passed)"
