#!/usr/bin/env bash
# test-validate-links.sh -- regression for the bare-script-name pipefail false-red
# (reported 2026-10-10): the verdict `find ... -print -quit | grep -q .` judged the
# PIPELINE exit under `set -uo pipefail`, so a permission-denied traversal error on
# an unrelated directory (find exit 1) flipped resolving names to errors even though
# grep matched (PIPESTATUS 1 0). The validator must judge by whether find produced
# a match instead.
#
# Half A: a resolving name alongside an erroring find exits 0. Half B: the same
# fixture with the file absent still exits 1 naming it (the fix must not swallow
# real misses). chmod cannot manufacture an unreadable directory on every platform
# this suite runs on, so the fixture shadows `find` with a shim that relays the
# real match output and exits 1 -- exactly the PIPESTATUS 1 0 condition from the
# report. A precondition asserts the shim relays a match with exit 1, so neither
# half can pass vacuously.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
VALIDATOR="$CORE/scripts/ci/validate-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-validate-links.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass=0

ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

fixture="$TMP/fixture"
mkdir -p "$fixture/plugins/sefi-core/scripts/ci" "$fixture/docs" "$TMP/bin"
cp "$VALIDATOR" "$fixture/plugins/sefi-core/scripts/ci/validate-links.sh"

# One scanned doc naming one script with no path (the bare-name surface).
printf '# Probe\n\nRun `probe-present.sh` to check.\n' >"$fixture/docs/PROBE.md"
printf '#!/usr/bin/env bash\n' >"$fixture/plugins/sefi-core/scripts/probe-present.sh"
git -C "$fixture" init -q 2>/dev/null
git -C "$fixture" config user.email 'ci@example.com'
git -C "$fixture" config user.name 'CI'
git -C "$fixture" config core.autocrlf false
git -C "$fixture" add -A

# Shim over the real find: relay its stdout, mimic a traversal error on stderr,
# and exit 1 the way find does when an unrelated directory denies traversal.
REAL_FIND="$(command -v find)"
cat >"$TMP/bin/find" <<EOF
#!/usr/bin/env bash
output="\$("$REAL_FIND" "\$@")"
[ -n "\$output" ] && printf '%s\n' "\$output"
echo "find: './unrelated-cache': Permission denied" >&2
exit 1
EOF
chmod +x "$TMP/bin/find"

# Precondition: the fixture really reproduces PIPESTATUS 1 0 (match + exit 1).
set +e
shim_out="$(PATH="$TMP/bin:$PATH" find "$fixture" -name 'probe-present.sh' -print -quit 2>/dev/null)"
shim_code=$?
set -e
if [ "$shim_code" -eq 1 ] && [ -n "$shim_out" ]; then
  ok "fixture reproduces PIPESTATUS 1 0 (match relayed, find exit 1)"
else
  bad "fixture reproduces PIPESTATUS 1 0 (exit $shim_code, output '$shim_out')"
fi

# Half A: resolving name alongside an erroring find exits 0.
if PATH="$TMP/bin:$PATH" bash "$fixture/plugins/sefi-core/scripts/ci/validate-links.sh" >/dev/null 2>&1; then
  ok "resolving name alongside erroring find exits 0"
else
  bad "resolving name alongside erroring find exits 0"
fi

# Half B: the same fixture with the file absent still exits 1 naming it.
# Plain rm (not git rm): with a staged-but-uncommitted fixture, line-ending
# normalization can make git rm refuse without -f; rm plus un-staging is exact.
rm "$fixture/plugins/sefi-core/scripts/probe-present.sh"
git -C "$fixture" rm -q --cached -- 'plugins/sefi-core/scripts/probe-present.sh'
set +e
missing_out="$(PATH="$TMP/bin:$PATH" bash "$fixture/plugins/sefi-core/scripts/ci/validate-links.sh" 2>&1)"
missing_code=$?
set -e
case "$missing_out" in
  *probe-present.sh*) named=0 ;;
  *) named=1 ;;
esac
if [ "$missing_code" -eq 1 ] && [ "$named" -eq 0 ]; then
  ok "absent file still exits 1 naming it"
else
  bad "absent file still exits 1 naming it (exit $missing_code, output '$missing_out')"
fi

if [ "$fail" -ne 0 ]; then echo "test-validate-links: $fail failure(s)"; exit 1; fi
echo "test-validate-links: PASS ($pass checks)"
