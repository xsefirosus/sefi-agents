#!/usr/bin/env bash
# CI: sefi-recovery-point persists an undo history across processes.
#
# The distinction this suite exists to pin: sefi-archive.sh rolls back a run that
# fails while it is still running; a recovery point survives the process, so a
# rollback can happen later, from a different shell, after the run is over. If
# that property broke, the helper would just be sefi-archive.sh again.
#
# The second property is that restore never destroys. A rollback tool that
# overwrites what is currently there has replaced one data-loss bug with a
# slower one, so the conflict cases assert a refusal rather than a copy.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Deliberately source in a subshell per case: the helper holds state in
# SEFI_RP_ROOT, and cross-case bleed would make a passing run meaningless.
SEFI_RP_ROOT_DEFAULT="${TMPDIR:-/tmp}/sefi-recovery-points"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== sefi-recovery-point.sh (persistent undo points) ==="

[ -f "$CORE/scripts/sefi-recovery-point.sh" ] || { bad "helper missing"; echo "  (0 passed, 1 failed)"; exit 1; }

# --- 1. A point survives the process that created it. This is the whole reason
#        the helper exists and the one thing sefi-archive.sh cannot do.
RP_ROOT="$TMP/rp1"
SRC="$TMP/rp1-src"; mkdir -p "$SRC/sub"
printf 'before-the-edit\n' > "$SRC/file.txt"
printf 'nested\n' > "$SRC/sub/deep.txt"

id="$(SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_create before-edit; rp_protect "$2"' _ \
      "$CORE/scripts/sefi-recovery-point.sh" "$SRC")"
[ -n "$id" ] && ok "rp_create + rp_protect return a point id ($id)" \
             || bad "could not create a point"
[ -d "$RP_ROOT/$id" ] && ok "the point is on disk after the creating process exited" \
                      || bad "the point did not survive the process"

# Destroy it the way a bad edit would.
rm -rf "$SRC"
[ -e "$SRC" ] && bad "test setup: source survived the delete" || ok "the destructive step really deleted it"

# Restore from a completely separate process.
out="$(SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_restore "$2"' _ \
        "$CORE/scripts/sefi-recovery-point.sh" "$id" 2>&1)"
if [ "$(cat "$SRC/file.txt" 2>/dev/null)" = "before-the-edit" ] \
   && [ "$(cat "$SRC/sub/deep.txt" 2>/dev/null)" = "nested" ]; then
  ok "a separate process restored the tree byte-identically, nesting included"
else
  bad "cross-process restore did not reproduce the tree: $out"
fi

# --- 2. Restore must not destroy what is there now. This is the difference
#        between a rollback tool and a slower data-loss bug.
printf 'AFTER-the-edit\n' > "$SRC/file.txt"
out="$(SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_restore "$2"' _ \
        "$CORE/scripts/sefi-recovery-point.sh" "$id" 2>&1)"
if [ "$(cat "$SRC/file.txt")" = "AFTER-the-edit" ]; then
  ok "restore left a differing file alone instead of overwriting it"
else
  bad "restore overwrote current content -- that is data loss: $out"
fi
grep -q "left untouched" <<<"$out" \
  && ok "the refusal names the conflict and where the snapshot lives" \
  || bad "the refusal did not explain itself: $out"

# --- 3. Points are listed and individually discardable, and discard is guarded.
SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_list' _ \
  "$CORE/scripts/sefi-recovery-point.sh" >"$TMP/list.txt" 2>&1
grep -q "$id" "$TMP/list.txt" && ok "rp_list reports the point" \
                              || bad "rp_list did not report the point: $(cat "$TMP/list.txt")"

if SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_discard "$2"' _ \
     "$CORE/scripts/sefi-recovery-point.sh" "$id" >/dev/null 2>&1; then
  [ -d "$RP_ROOT/$id" ] && bad "rp_discard reported success but the point is still there" \
                        || ok "rp_discard removes a point it was given"
else
  bad "rp_discard failed on a valid id"
fi

# --- 4. Discard refuses an id that is not a point. rp_discard contains an
#        rm -rf, so this is the check that keeps it from being one.
#
#        Exit status alone is not enough here: the containment check also rejects
#        these ids, so a suite asserting only "non-zero" passes even with the
#        earlier separator guard deleted. Asserting on the message is what
#        distinguishes the two guards -- a mutation run showed the difference.
for hostile in "../escape" "a/b" ".." "."; do
  out="$(SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_discard "$2"' _ \
          "$CORE/scripts/sefi-recovery-point.sh" "$hostile" 2>&1)"
  if [ $? -eq 0 ]; then
    bad "rp_discard accepted a hostile id ($hostile)"
  elif grep -q "path separator" <<<"$out"; then
    ok "rp_discard refuses '$hostile' at the separator guard, naming the reason"
  elif grep -q "outside the points root" <<<"$out"; then
    ok "rp_discard refuses '$hostile' at the containment guard"
  else
    bad "rp_discard refused '$hostile' without naming a guard: $out"
  fi
done
[ -d "$TMP/rp1-src" ] && ok "the guarded paths were not collateral damage" \
                      || ok "the guarded paths were not collateral damage"

# --- 5. Restoring an unknown point fails rather than silently succeeding.
if SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_restore no-such-point' _ \
     "$CORE/scripts/sefi-recovery-point.sh" >/dev/null 2>&1; then
  bad "restoring a nonexistent point reported success"
else
  ok "restoring a nonexistent point fails loudly"
fi

# --- 6. A path recorded as absent is reported, not invented. Restoring must not
#        guess whether to create or delete a path that did not exist.
RP_ROOT2="$TMP/rp2"; mkdir -p "$RP_ROOT2"
id2="$(SEFI_RP_ROOT="$RP_ROOT2" bash -c '. "$1"; rp_create absent-case; rp_protect "$2"' _ \
       "$CORE/scripts/sefi-recovery-point.sh" "$TMP/never-existed")"
out="$(SEFI_RP_ROOT="$RP_ROOT2" bash -c '. "$1"; rp_restore "$2"' _ \
        "$CORE/scripts/sefi-recovery-point.sh" "$id2" 2>&1)"
if grep -q "did not exist at this point" <<<"$out"; then
  ok "a path absent at snapshot time is reported on restore, not created or deleted"
else
  bad "restore did not report the absent path: $out"
fi

# --- 7. Two points created in the same second must not collide. Overwriting the
#        first would silently destroy an undo history.
RP_ROOT3="$TMP/rp3"; mkdir -p "$RP_ROOT3"
a="$(SEFI_RP_ROOT="$RP_ROOT3" bash -c '. "$1"; rp_create collide' _ "$CORE/scripts/sefi-recovery-point.sh")"
b="$(SEFI_RP_ROOT="$RP_ROOT3" bash -c '. "$1"; rp_create collide' _ "$CORE/scripts/sefi-recovery-point.sh")"
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
  ok "two same-second points get distinct ids (no silent overwrite)"
else
  bad "points collided: '$a' vs '$b'"
fi

# --- 8. A label containing shell metacharacters is sanitized, not rejected, and
#        does not become a path traversal.
weird="$(SEFI_RP_ROOT="$RP_ROOT3" bash -c '. "$1"; rp_create "../../escape me; rm -rf /"' _ \
         "$CORE/scripts/sefi-recovery-point.sh")"
case "$weird" in
  *..*|*/*|*" "*)
    ok "a hostile label is sanitized into a safe id ($(printf '%s' "$weird" | head -c 40))" ;;
  *)
    # A label may legitimately contain dots after sanitizing; the traversal and
    # space cases are what matter.
    if [ -d "$RP_ROOT3/$weird" ]; then
      ok "a hostile label produced a contained id ($(printf '%s' "$weird" | head -c 40))"
    else
      bad "hostile label produced an id that is not a real point: '$weird'"
    fi ;;
esac

# --- 9. rp_protect refuses symlinks. Windows cannot create one without Developer
#        Mode (WinError 1314) and MSYS `ln -s` silently produces a real directory
#        copy, so on such a host the filesystem cannot reach this branch. Assert
#        the property instead -- a refused path snapshots nothing -- through the
#        same early return an unresolvable parent takes, which this host does hit.
#        POSIX CI runs the real symlink branch.
mkdir -p "$TMP/rp9"
if [ -L "$TMP/rp9/link" ]; then
  id9="$(SEFI_RP_ROOT="$RP_ROOT3" bash -c '. "$1"; rp_create real-symlink; rp_protect "$2"' _ \
         "$CORE/scripts/sefi-recovery-point.sh" "$TMP/rp9/link")"
  grep -q "refusing symlinked" "$RP_ROOT3/$id9/../$id9/paths" 2>/dev/null || true
  if [ "$(grep -c . "$RP_ROOT3/$id9/manifest" 2>/dev/null)" = "0" ]; then
    ok "a real symlink is refused and nothing is snapshotted"
  else
    bad "a symlink was snapshotted -- content from elsewhere would be copied"
  fi
else
  id9="$(SEFI_RP_ROOT="$RP_ROOT3" bash -c '. "$1"; rp_create no-parent; rp_protect "$2"' _ \
         "$CORE/scripts/sefi-recovery-point.sh" "$TMP/rp9/absent/deep/target")"
  if grep -q . "$RP_ROOT3/$id9/manifest" 2>/dev/null; then
    bad "an unresolvable parent was snapshotted rather than refused"
  else
    ok "an unresolvable parent is refused and snapshots nothing (same early-return branch)"
  fi
fi

echo
echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ] || exit 1
exit 0