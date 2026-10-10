#!/usr/bin/env bash
# CI: install-hermes.sh --auto-update must actually re-fetch installed skills.
#
# `hermes skills install` SKIPS an already-installed skill ("Warning: 'x' is already
# installed ... Use --force to reinstall"). So a refresh run that omits --force
# re-fetches nothing, and the installer's own byte-comparison then reports the
# PRE-EXISTING content as a mismatch. Live failure, Windows/git-bash 2026-10-06:
# `--auto-update` refreshed the managed runtime correctly, left 2 of 20 skills
# stale, and exited 1 with "fetched skill content differs from the expected
# source: release-tracking".
#
# There is no way to update an installed skill without --force, so a refresh run has
# to use it for every skill. These cases pin that decision, and pin the opposite
# case too: a plain first-time install must NOT blanket-force, or it would bypass
# the community-skill security scanner for all 20 skills on every fresh install.
#
# The logic is extracted rather than sourced, so the suite never runs a 20-skill
# live install against the user's real Hermes home.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$CORE/scripts/install-hermes.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "=== install-hermes.sh --auto-update refreshes installed skills ==="

[ -f "$INSTALLER" ] || { bad "installer missing"; echo "  (0 passed, 1 failed)"; exit 1; }

# --- The shipped in_force, extracted from the installer with the same FORCE_SKILLS
#     the installer declares, so this cannot pass against a stale copy of the logic.
FORCE_SKILLS="$(sed -n 's/^FORCE_SKILLS="\(.*\)"$/\1/p' "$INSTALLER" | head -1)"
[ -n "$FORCE_SKILLS" ] || { bad "could not read FORCE_SKILLS from the installer";                            echo "  (0 passed, 1 failed)"; exit 1; }

in_force_from_installer() {
  local auto="$1" name="$2" f
  for f in $FORCE_SKILLS; do
    [ "$f" = "$name" ] && return 0
  done
  [ "$auto" -eq 1 ] && return 0
  return 1
}

# The two scanner-override skills keep their original reason in BOTH modes.
for s in $FORCE_SKILLS; do
  in_force_from_installer 0 "$s" && ok "$s is forced without --auto-update (scanner-substring reason)" \
                          || bad "$s lost its scanner-substring force"
  in_force_from_installer 1 "$s" && ok "$s is forced with --auto-update" \
                          || bad "$s should be forced with --auto-update"
done

# The live failure: release-tracking is an ordinary skill, so only --auto-update
# forces it. If this regresses, the exact observed failure returns.
if in_force_from_installer 1 release-tracking; then
  ok "release-tracking is force-refreshed under --auto-update (the live failure)"
else
  bad "release-tracking is not forced under --auto-update -- the observed stale-skill failure returns"
fi
if in_force_from_installer 0 release-tracking; then
  bad "release-tracking must NOT be forced on a plain install (would bypass the scanner for all 20)"
else
  ok "release-tracking is not forced on a plain first-time install"
fi

# A spread of ordinary skills behaves the same way in refresh mode.
for s in systems-audit loop-engineering memory-journalist qa-engineering; do
  in_force_from_installer 1 "$s" \
    && ok "$s is force-refreshed under --auto-update" \
    || bad "$s must be force-refreshed under --auto-update"
done

# --- The installer must actually consult AUTO_UPDATE inside in_force, not just
#     declare the variable. A future edit could drop the line and leave this suite
#     green because it only tests the extracted copy.
if grep -qE '\[ "\$AUTO_UPDATE" -eq 1 \] && return 0' "$INSTALLER"; then
  ok "the shipped in_force consults AUTO_UPDATE (the extracted copy is not the only source of truth)"
else
  bad "install-hermes.sh in_force does not consult AUTO_UPDATE -- skills will never be re-fetched"
fi

# --- And the fetch loop must route through in_force, not call hermes skills install
#     directly with a hardcoded flag set.
if grep -q 'if in_force "\$name"; then' "$INSTALLER"; then
  ok "the fetch loop routes through in_force"
else
  bad "the fetch loop no longer consults in_force -- the force decision is bypassed"
fi

echo
echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ] || exit 1
exit 0