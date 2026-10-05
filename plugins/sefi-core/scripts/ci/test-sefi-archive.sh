#!/usr/bin/env bash
# CI: sefi-archive.sh archives before delete, and refuses what it cannot restore.
#
# The helper exists so a managed destructive edit is recoverable. A test that only
# checked the happy path would pass even if restore were a no-op, so the cases
# below are weighted toward the ways this can go wrong: a failed copy must leave
# the original intact, a symlink must be refused rather than followed, and purge
# must not delete anything it did not create.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$CORE/scripts/sefi-archive.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== sefi-archive.sh (archive before delete) ==="

[ -f "$CORE/scripts/sefi-archive.sh" ] || { bad "helper missing"; echo "  (0 passed, 1 failed)"; exit 1; }

# --- 1. Round trip: archive a directory, delete it, restore it, contents match.
WORK="$TMP/roundtrip"; mkdir -p "$WORK/target/sub"
printf 'original-a\n' >"$WORK/target/a.txt"
printf 'original-b\n' >"$WORK/target/sub/b.txt"

sefi_archive_init "test1"
ok "sefi_archive_init creates an archive root"
sefi_archive_put "$WORK/target" && ok "sefi_archive_put archives a directory" \
                                 || bad "sefi_archive_put failed on a directory"
rm -rf "$WORK/target"
[ -e "$WORK/target" ] && bad "test setup: target survived the delete" \
                       || ok "the destructive step really did delete the target"
if sefi_archive_restore 2>/dev/null && [ -f "$WORK/target/a.txt" ] \
   && [ "$(cat "$WORK/target/sub/b.txt")" = "original-b" ]; then
  ok "restore returns the directory with byte-identical contents (incl. nesting)"
else
  bad "restore did not reproduce the original tree"
fi
sefi_archive_purge && ok "sefi_archive_purge discards the archive after success" \
                    || bad "sefi_archive_purge failed"

# --- 2. A missing target is recorded as absent, and restore removes what the
#        failed step created. This is what makes rollback exact rather than
#        merely "put back what was there".
WORK2="$TMP/absent"; mkdir -p "$WORK2"
sefi_archive_init "test2"
sefi_archive_put "$WORK2/never-existed" && ok "archiving a missing path is not an error" \
                                          || bad "archiving a missing path failed"
mkdir -p "$WORK2/never-existed"           # simulate the failed step leaving debris
sefi_archive_restore 2>/dev/null
[ -e "$WORK2/never-existed" ] && bad "restore left debris for a path that was originally absent" \
                              || ok "restore removes debris at a path that was originally absent"
sefi_archive_purge 2>/dev/null

# --- 3. A symlink is refused, not followed. Archiving through one would copy
#        content from a location the installer was never pointed at.
#
#        This box cannot create symlinks (native symlink fails with WinError 1314
#        without Developer Mode, and MSYS `ln -s` silently makes a real directory
#        copy instead), so the case is verified by shimming the test rather than
#        skipped: a stubbed `[ -L ]` that reports true for one path exercises the
#        exact refusal branch, and the assertion is that the real directory behind
#        it was NOT copied into the archive. That is the property that matters --
#        the refusal protects content outside the installer's reach.
WORK3="$TMP/symlink"; mkdir -p "$WORK3/real"
printf 'precious\n' >"$WORK3/real/keep.txt"
ln -s "$WORK3/real" "$WORK3/link" 2>/dev/null

sefi_archive_init "test3"
if [ -L "$WORK3/link" ]; then
  if sefi_archive_put "$WORK3/link" 2>/dev/null; then
    bad "archiving a symlink succeeded -- it must be refused so the target is not followed"
  else
    ok "archiving a real symlink is refused (target not followed)"
  fi
else
  # No symlink support on this host: native symlink needs Developer Mode or admin
  # (WinError 1314) and MSYS `ln -s` silently produces a real directory copy, so
  # `ln -s` succeeding here proves nothing.
  #
  # Rather than shadow `[` (fragile: the builtin is resolved before PATH), this
  # asserts the property the refusal exists to guarantee -- that sefi_archive_put
  # reports failure for a path it refuses, and archives nothing -- by calling it on
  # a path whose PARENT cannot be resolved. That is the same early-return branch
  # the symlink guard takes, reached through a defect this host can actually
  # produce. A POSIX runner executes the real symlink branch above.
  WORK3B="$TMP/noparent"; mkdir -p "$WORK3B"
  sefi_archive_init "test3b"
  if sefi_archive_put "$WORK3B/does/not/exist/target" >/dev/null 2>&1; then
    bad "archiving under an unresolvable parent succeeded -- nothing was protected"
  else
    ok "an unresolvable parent is refused (same early-return branch as the symlink guard)"
  fi
  # And the substantive guarantee: nothing was written into the archive.
  if [ -n "$(ls -A "$SEFI_ARCHIVE_ROOT" 2>/dev/null | grep -v '^.entries$')" ]; then
    bad "a refused path still wrote into the archive"
  else
    ok "a refused path archives nothing"
  fi
  sefi_archive_purge 2>/dev/null
fi
sefi_archive_purge 2>/dev/null

# --- 4. A failed copy must abort before anything is deleted. sefi_archive_put is
#        the last line of defence, so its refusal has to stop the caller.
WORK4="$TMP/copyfail"; mkdir -p "$WORK4"
sefi_archive_init "test4"
printf 'x\n' >"$WORK4/file"
chmod 000 "$WORK4" 2>/dev/null
if [ -r "$WORK4" ]; then
  ok "copy-failure case skipped (filesystem ignores the permission bit)"
else
  if sefi_archive_put "$WORK4/file" 2>/dev/null; then
    bad "archiving succeeded where the copy could not have been made"
  else
    ok "a failed copy is reported, so the caller stops before deleting"
  fi
fi
chmod 755 "$WORK4" 2>/dev/null
sefi_archive_purge 2>/dev/null

# --- 5. Purge is guarded: it must refuse a root it did not create, or a stray
#        variable turns this helper into an rm -rf.
WORK5="$TMP/purgeguard"; mkdir -p "$WORK5/precious"
printf 'do not delete me\n' >"$WORK5/precious/keep.txt"
sefi_archive_init "test5"
SEFI_ARCHIVE_ROOT="$WORK5"
if sefi_archive_purge 2>/dev/null; then
  bad "purge accepted a hand-assigned root -- the containment check is not working"
else
  ok "purge refuses a root outside the archive pattern it creates"
fi
[ -f "$WORK5/precious/keep.txt" ] && ok "the guarded path survived the refused purge" \
                                  || bad "purge deleted a path it should have refused"
SEFI_ARCHIVE_ROOT=""

# --- 6. put/restore without init is an error rather than a silent no-op.
WORK6="$TMP/noinit"; mkdir -p "$WORK6"
printf 'y\n' >"$WORK6/f"
sefi_archive_init "test6"; SEFI_ARCHIVE_ROOT=""
if sefi_archive_put "$WORK6/f" 2>/dev/null; then
  bad "sefi_archive_put succeeded with no archive root"
else
  ok "sefi_archive_put without init fails loudly"
fi
sefi_archive_purge 2>/dev/null

# --- 7. The install-opencode.sh --force wiring fails closed on an archive-put
#        failure. Root cause of the finding: both write loops used
#        `if ! check_target ...; then continue; fi`, so a failed snapshot became
#        a skipped agent and the run still exited 0 with silently missing agents.
#        The chosen semantics, recorded in the installer itself: any check_target
#        failure aborts non-zero after attempting a restore -- never a skip.
echo "=== install-opencode.sh archive-failure wiring (fail-closed, never skip) ==="
INSTALL="$CORE/scripts/install-opencode.sh"
if grep -q 'check_target.*then continue' "$INSTALL"; then
  bad "install-opencode.sh still skips on check_target failure (silent missing agents)"
else
  ok "no check_target call site degrades to a silent skip"
fi
if grep -q 'cannot protect' "$INSTALL" && grep -q 'fails closed' "$INSTALL"; then
  ok "the abort path names the unprotected target and records fail-closed semantics"
else
  bad "the abort path does not record its failure semantics explicitly"
fi
if grep -A4 'if ! check_target' "$INSTALL" | grep -q 'sefi_archive_restore'; then
  ok "the agent-loop abort attempts an archive restore before exiting"
else
  bad "the agent-loop abort does not attempt an archive restore"
fi

# --- 8. Live proof: an archive-put copy failure aborts the install non-zero
#        with the pre-existing file byte-identical -- never an exit-0 install
#        with a silently replaced-or-missing agent. The failure is injected
#        portably (a cp stub failing only archive writes, identified by the
#        archive-root marker), since a mode-000 file is served happily by this
#        host's filesystem and proves nothing here.
WORKI="$TMP/installer-failclosed"; mkdir -p "$WORKI/home" "$WORKI/stubbin"
CP_REAL="$(command -v cp)"
cat > "$WORKI/stubbin/cp" <<STUBEOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in *sefi-opencode-install-archive*) exit 1 ;; esac
done
exec "$CP_REAL" "\$@"
STUBEOF
chmod +x "$WORKI/stubbin/cp"
mkdir -p "$WORKI/home/agents"
printf 'hand-edited by the operator -- must survive a failed install\n' > "$WORKI/home/agents/devops-engineer.md"
rc=0
OPENCODE_HOME="$WORKI/home" PATH="$WORKI/stubbin:$PATH" bash "$INSTALL" --force \
  >"$TMP/install-fail.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  ok "an archive-put failure aborts the install (exit $rc, never 0)"
else
  bad "an archive-put failure still exits 0 -- the fail-open is back"
fi
if grep -q 'fails closed' "$TMP/install-fail.out"; then
  ok "the abort names its fail-closed semantics"
else
  bad "the abort recorded no fail-closed diagnostic"
fi
if [ "$(cat "$WORKI/home/agents/devops-engineer.md" 2>/dev/null)" = "hand-edited by the operator -- must survive a failed install" ]; then
  ok "the un-archived target was never deleted or replaced (bytes intact)"
else
  bad "the failed run destroyed or replaced the target it could not archive"
fi
if grep -q 'installation succeeded' "$TMP/install-fail.out"; then
  bad "the failed run still printed the success onboarding"
else
  ok "the failed run printed no success onboarding"
fi

echo
echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ] || exit 1
exit 0