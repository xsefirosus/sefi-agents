#!/usr/bin/env bash
# test-manifest-version.sh -- install version-tracking fixtures. Every assertion targets
# the version-identity contract: manifest create records source_version/source_commit,
# manifest diff reports current/stale/drift, legacy manifests (no new fields) read as
# UNKNOWN, untagged sources record unreleased-plus-commit, non-checkouts record
# UNKNOWN/UNKNOWN, manifest check behavior is unchanged, and both installers honor
# --auto-update without silently overwriting user edits.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
RUNTIME="$CORE/scripts/sefi-runtime.py"
FIX="$CORE/scripts/ci/fixtures/manifest-version"

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

PYBIN=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
    PYBIN="$candidate"
    break
  fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: test-manifest-version (Python 3.11+ unavailable; CI always has it)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rt() { "$PYBIN" "$RUNTIME" manifest "$@"; }

json_field() {
  # json_field <file> <key> -- print the string value, or empty when absent.
  "$PYBIN" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], ""))' "$1" "$2"
}

git_repo() {
  # git_repo <dir> -- init a repo with src/file.txt committed; echoes HEAD.
  mkdir -p "$1/src"
  printf 'version fixture one\n' > "$1/src/file.txt"
  git -C "$1" -c init.defaultBranch=main init -q >&2
  git -C "$1" -c user.email=fixture@test -c user.name=fixture add src/file.txt >&2
  git -C "$1" -c user.email=fixture@test -c user.name=fixture commit -qm fixture >&2
  git -C "$1" rev-parse HEAD
}

echo "=== fixture 1: create records source_version/source_commit ==="
R1="$TMP/r1"
HEAD1="$(git_repo "$R1")"
git -C "$R1" tag v9.9.9-fixture >&2
D1="$TMP/d1"
mkdir -p "$D1"
cp "$R1/src/file.txt" "$D1/"
expect_code 0 "create exits 0" rt create --root "$TMP" --source "$R1/src" --destination "$D1"
[ "$(json_field "$D1/.sefi-agents-manifest.json" source_version)" = "v9.9.9-fixture" ] \
  && ok "created manifest records the source commit tag" \
  || bad "created manifest version is $(json_field "$D1/.sefi-agents-manifest.json" source_version), wanted v9.9.9-fixture"
[ "$(json_field "$D1/.sefi-agents-manifest.json" source_commit)" = "$HEAD1" ] \
  && ok "created manifest records the source commit" \
  || bad "created manifest commit does not match HEAD"

echo
echo "=== fixture 2: diff-current (hashes and version match) ==="
out="$(rt diff --root "$TMP" --source "$R1/src" --destination "$D1" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diff-current exits 0" || bad "diff-current exited $rc: $out"
case "$out" in
  *"package-manifest-diff: current"*) ok "diff-current names the current verdict" ;;
  *) bad "diff-current printed no current verdict: $out" ;;
esac

echo
echo "=== fixture 3: diff-stale (source moved on; names new version and commit) ==="
printf 'version fixture two\n' > "$R1/src/file.txt"
git -C "$R1" -c user.email=fixture@test -c user.name=fixture commit -qam second >&2
git -C "$R1" tag v10.0.0-fixture >&2
HEAD2="$(git -C "$R1" rev-parse HEAD)"
out="$(rt diff --root "$TMP" --source "$R1/src" --destination "$D1" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "diff-stale exits 2" || bad "diff-stale exited $rc: $out"
case "$out" in
  *"package-manifest-diff: stale"*) ok "diff-stale names the stale verdict" ;;
  *) bad "diff-stale printed no stale verdict: $out" ;;
esac
case "$out" in
  *"v10.0.0-fixture"*) ok "diff-stale names the new version" ;;
  *) bad "diff-stale names no new version: $out" ;;
esac
case "$out" in
  *"$HEAD2"*) ok "diff-stale names the new commit" ;;
  *) bad "diff-stale names no new commit: $out" ;;
esac

echo
echo "=== fixture 4: diff-drift (names user-modified installed files; check unchanged) ==="
R4="$TMP/r4"
git_repo "$R4" > /dev/null
D4="$TMP/d4"
mkdir -p "$D4"
cp "$R4/src/file.txt" "$D4/"
expect_code 0 "create exits 0" rt create --root "$TMP" --source "$R4/src" --destination "$D4"
expect_code 0 "check on a clean install still exits 0" rt check --root "$TMP" --destination "$D4"
printf 'user edit\n' >> "$D4/file.txt"
out="$(rt diff --root "$TMP" --source "$R4/src" --destination "$D4" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "diff-drift exits 1" || bad "diff-drift exited $rc: $out"
case "$out" in
  *"package-manifest-diff: drift"*) ok "diff-drift names the drift verdict" ;;
  *) bad "diff-drift names nothing: $out" ;;
esac
case "$out" in
  *"file.txt"*) ok "diff-drift names the modified file" ;;
  *) bad "diff-drift names no modified file: $out" ;;
esac
check_out="$(rt check --root "$TMP" --destination "$D4" 2>&1)"; check_rc=$?
[ "$check_rc" -eq 1 ] && ok "check on a drifted install still exits 1" || bad "check on drift exited $check_rc"
case "$check_out" in
  *"drift in managed files"*) ok "check keeps its byte-identical drift message" ;;
  *) bad "check drift message changed: $check_out" ;;
esac

echo
echo "=== fixture 5: legacy manifest without fields reads as UNKNOWN ==="
D5="$TMP/d5"
mkdir -p "$D5"
cp "$FIX/legacy/file.txt" "$FIX/legacy/.sefi-agents-manifest.json" "$D5/"
[ "$(json_field "$D5/.sefi-agents-manifest.json" source_version)" = "" ] \
  && ok "legacy fixture really carries no source_version" \
  || bad "legacy fixture unexpectedly carries source_version"
R5="$TMP/r5"
mkdir -p "$R5/src"
cp "$FIX/legacy/file.txt" "$R5/src/file.txt"
git -C "$R5" -c init.defaultBranch=main init -q >&2
git -C "$R5" -c user.email=fixture@test -c user.name=fixture add src/file.txt >&2
git -C "$R5" -c user.email=fixture@test -c user.name=fixture commit -qm fixture >&2
git -C "$R5" tag v5.5.5-fixture >&2
HEAD5="$(git -C "$R5" rev-parse HEAD)"
out="$(rt diff --root "$TMP" --source "$R5/src" --destination "$D5" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "legacy manifest diffs as stale (exit 2), not current" || bad "legacy diff exited $rc: $out"
case "$out" in
  *"v5.5.5-fixture"*) ok "legacy stale names the new version" ;;
  *) bad "legacy stale names no new version: $out" ;;
esac
case "$out" in
  *"$HEAD5"*) ok "legacy stale names the new commit" ;;
  *) bad "legacy stale names no new commit: $out" ;;
esac

echo
echo "=== fixture 6: untagged source records unreleased-plus-commit ==="
R6="$TMP/r6"
HEAD6="$(git_repo "$R6")"
D6="$TMP/d6"
mkdir -p "$D6"
cp "$R6/src/file.txt" "$D6/"
expect_code 0 "create on an untagged source exits 0" rt create --root "$TMP" --source "$R6/src" --destination "$D6"
[ "$(json_field "$D6/.sefi-agents-manifest.json" source_version)" = "unreleased-plus-$HEAD6" ] \
  && ok "untagged source records unreleased-plus-commit, never a guessed release" \
  || bad "untagged version is $(json_field "$D6/.sefi-agents-manifest.json" source_version)"
[ "$(json_field "$D6/.sefi-agents-manifest.json" source_commit)" = "$HEAD6" ] \
  && ok "untagged source still records the commit" \
  || bad "untagged commit does not match HEAD"
out="$(rt diff --root "$TMP" --source "$R6/src" --destination "$D6" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "untagged diff-current exits 0" || bad "untagged diff exited $rc: $out"

echo
echo "=== fixture 7: outside a git checkout both values are UNKNOWN ==="
if git -C "$TMP" rev-parse HEAD >/dev/null 2>&1; then
  echo "  SKIP: scratch dir unexpectedly lives inside a git checkout"
else
  S7="$TMP/plain7/src"
  D7="$TMP/plain7/dst"
  mkdir -p "$S7" "$D7"
  printf 'plain fixture\n' > "$S7/file.txt"
  cp "$S7/file.txt" "$D7/"
  expect_code 0 "create outside git exits 0" rt create --root "$TMP" --source "$S7" --destination "$D7"
  [ "$(json_field "$D7/.sefi-agents-manifest.json" source_version)" = "UNKNOWN" ] \
    && ok "non-checkout version falls back to UNKNOWN" \
    || bad "non-checkout version is $(json_field "$D7/.sefi-agents-manifest.json" source_version)"
  [ "$(json_field "$D7/.sefi-agents-manifest.json" source_commit)" = "UNKNOWN" ] \
    && ok "non-checkout commit falls back to UNKNOWN" \
    || bad "non-checkout commit is $(json_field "$D7/.sefi-agents-manifest.json" source_commit)"
  out="$(rt diff --root "$TMP" --source "$S7" --destination "$D7" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "UNKNOWN-to-UNKNOWN diff reads as current" || bad "non-checkout diff exited $rc: $out"
fi

echo
echo "=== fixture 8: install-opencode.sh --auto-update ==="
OC="$TMP/oc"
expect_code 0 "fresh --auto-update install exits 0" env OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" --auto-update
[ -f "$OC/scripts/.sefi-agents-manifest.json" ] \
  && ok "fresh install writes a scripts manifest" \
  || bad "fresh install wrote no scripts manifest"
oc_commit="$(json_field "$OC/scripts/.sefi-agents-manifest.json" source_commit)"
[ "$oc_commit" = "$(git -C "$ROOT" rev-parse HEAD)" ] \
  && ok "installer manifest derives the commit from the checkout" \
  || bad "installer manifest commit is $oc_commit"
[ -n "$(json_field "$OC/scripts/.sefi-agents-manifest.json" source_version)" ] \
  && ok "installer manifest records a version" \
  || bad "installer manifest records no version"
out="$(OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "second --auto-update exits 0" || bad "second --auto-update exited $rc: $out"
case "$out" in
  *"nothing to do"*) ok "diff-current does nothing on the second run" ;;
  *) bad "second run did not report nothing-to-do: $out" ;;
esac
printf 'user edit\n' >> "$OC/scripts/gate.sh"
out="$(OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "diff-drift stops with an error" || bad "drifted --auto-update exited $rc: $out"
case "$out" in
  *"refusing"*|*"gate.sh"*) ok "drift error asks instead of overwriting" ;;
  *) bad "drift error says nothing useful: $out" ;;
esac
case "$out" in
  *"gate.sh"*) ok "drift error names the modified file" ;;
  *) bad "drift error names no file: $out" ;;
esac
# Drift takes precedence over staleness by design, so restore the drifted file
# before proving the version-only stale path.
cp "$CORE/scripts/gate.sh" "$OC/scripts/gate.sh"
"$PYBIN" - "$OC/scripts/.sefi-agents-manifest.json" <<'PYEOF'
import json
import sys
path = sys.argv[1]
payload = json.load(open(path, encoding="utf-8"))
payload["source_version"] = "v0.0.0-stale-fixture"
json.dump(payload, open(path, "w", encoding="utf-8"), indent=2, sort_keys=True)
PYEOF
out="$(OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diff-stale performs the normal install" || bad "stale --auto-update exited $rc: $out"
[ "$(json_field "$OC/scripts/.sefi-agents-manifest.json" source_version)" != "v0.0.0-stale-fixture" ] \
  && ok "stale update rewrites the manifest version" \
  || bad "stale update left the stale version in place"
out="$(OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "post-update --auto-update converges to current" || bad "post-update run exited $rc: $out"

echo
echo "=== fixture 9: install-hermes.sh --auto-update (stubbed hermes CLI) ==="
expect_code 0 "hermes --help exits 0" bash "$CORE/scripts/install-hermes.sh" --help
if bash "$CORE/scripts/install-hermes.sh" --help 2>&1 | grep -q -- '--auto-update'; then
  ok "hermes usage advertises --auto-update"
else
  bad "hermes usage hides --auto-update"
fi
expect_code 2 "hermes unknown arg exits 2" bash "$CORE/scripts/install-hermes.sh" --bogus
STUB="$TMP/stubbin"
mkdir -p "$STUB"
export HERMES_STATE="$TMP/hermes-home"
export SEFI_SKILLS_SRC="$CORE/skills"
cat > "$STUB/hermes" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
state="${HERMES_STATE:?}/skills"
case "${1:-}" in
  config) [ "${2:-}" = "path" ] && printf '%s/config.yml\n' "${HERMES_STATE:?}" ;;
  skills)
    case "${2:-}" in
      install)
        name="${3##*/}"
        rm -rf "$state/$name"
        mkdir -p "$state"
        cp -r "$SEFI_SKILLS_SRC/$name" "$state/$name"
        ;;
      list)
        vbar="$(printf '\342\224\202 ')"
        for d in "$state"/*/; do
          [ -d "$d" ] || continue
          printf '%s%s %s\n' "$vbar" "$(basename "$d")" "$vbar"
        done
        ;;
    esac
    ;;
esac
STUBEOF
chmod +x "$STUB/hermes"
HDEST="$HERMES_STATE/skills"
expect_code 0 "stubbed normal install exits 0" env PATH="$STUB:$PATH" bash "$CORE/scripts/install-hermes.sh"
[ -f "$HDEST/.sefi-agents-version.json" ] \
  && ok "successful install records the version marker" \
  || bad "successful install recorded no version marker"
[ "$(json_field "$HDEST/.sefi-agents-version.json" source_commit)" = "$(git -C "$ROOT" rev-parse HEAD)" ] \
  && ok "hermes marker derives the commit from the checkout" \
  || bad "hermes marker commit is $(json_field "$HDEST/.sefi-agents-version.json" source_commit)"
out="$(PATH="$STUB:$PATH" bash "$CORE/scripts/install-hermes.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "hermes diff-current exits 0" || bad "hermes --auto-update exited $rc: $out"
case "$out" in
  *"nothing to do"*) ok "hermes diff-current does nothing" ;;
  *) bad "hermes second run did not report nothing-to-do: $out" ;;
esac
printf 'user edit\n' > "$HDEST/anti-hallucination/user-edit.txt"
out="$(PATH="$STUB:$PATH" bash "$CORE/scripts/install-hermes.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "hermes diff-drift stops with an error" || bad "hermes drifted --auto-update exited $rc: $out"
case "$out" in
  *"anti-hallucination"*) ok "hermes drift error names the modified skill" ;;
  *) bad "hermes drift error names no skill: $out" ;;
esac
"$PYBIN" - "$HDEST/.sefi-agents-version.json" <<'PYEOF'
import json
import sys
path = sys.argv[1]
payload = json.load(open(path, encoding="utf-8"))
payload["source_version"] = "v0.0.0-stale-fixture"
payload["source_commit"] = "stale"
json.dump(payload, open(path, "w", encoding="utf-8"), indent=2, sort_keys=True)
PYEOF
out="$(PATH="$STUB:$PATH" bash "$CORE/scripts/install-hermes.sh" --auto-update 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "hermes diff-stale performs the normal install" || bad "hermes stale --auto-update exited $rc: $out"
[ ! -e "$HDEST/anti-hallucination/user-edit.txt" ] \
  && ok "hermes stale update restores installed skills from source" \
  || bad "hermes stale update left user edits in place"
[ "$(json_field "$HDEST/.sefi-agents-version.json" source_version)" != "v0.0.0-stale-fixture" ] \
  && ok "hermes stale update refreshes the version marker" \
  || bad "hermes stale update left the stale marker in place"

echo
if [ "$fail" -ne 0 ]; then echo "test-manifest-version: $fail failed, $pass passed"; exit 1; fi
echo "test-manifest-version: OK ($pass passed)"
