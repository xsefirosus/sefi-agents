#!/usr/bin/env bash
# test-install-hermes-recovery-point.sh -- the sefi-commands plugin directory that
# install-hermes.sh deletes is recoverable through sefi-recovery-point.sh.
#
# Pre-agreed seams under test (fixed before the first assertion was written):
#   1. Source seam: install-hermes.sh sources sefi-recovery-point.sh before any
#      destructive call (line-number comparison, no hardcoded numbers).
#   2. Protect seam: the plugin-directory delete site guards rp_protect on
#      not-a-symlink, for the same reason install-opencode.sh guards its archive.
#   3. No-purge seam: the installer never calls rp_discard (points are kept until
#      a human explicitly discards one).
#   4. Restore seam: the failure path attempts rp_restore.
#   5. Behavioral seam: a plugin-shaped tree, protected in one process, deleted,
#      then restored from a separate process, comes back byte-identical.
#   6. Success seam: a clean stubbed install-hermes.sh run returns 0 and leaves
#      its recovery point in place.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
INSTALL="$CORE/scripts/install-hermes.sh"
HELPER="$CORE/scripts/sefi-recovery-point.sh"

fail=0
pass=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== install-hermes.sh recovery-point wiring ==="

[ -f "$INSTALL" ] || { bad "installer missing at $INSTALL"; echo "  ($pass passed, $fail failed)"; exit 1; }
[ -f "$HELPER" ] || { bad "helper missing at $HELPER"; echo "  ($pass passed, $fail failed)"; exit 1; }

# --- 1. The helper is sourced next to the installer's other helpers. ---
if grep -q 'sefi-recovery-point\.sh' "$INSTALL"; then
  ok "install-hermes.sh sources sefi-recovery-point.sh"
else
  bad "install-hermes.sh does not reference sefi-recovery-point.sh"
fi

# --- 2. Sourcing precedes the first destructive call. Line numbers are read off
#        the script, never hardcoded: the unprotected site was found by reading
#        install_commands_plugin's rm -rf of the plugin directory.
src_line="$(grep -n '\. "\$RECOVERY_POINT"' "$INSTALL" | head -1 | cut -d: -f1)"
[ -z "$src_line" ] && src_line="$(grep -n 'sefi-recovery-point\.sh' "$INSTALL" | head -1 | cut -d: -f1)"
first_rm="$(grep -n 'rm -rf' "$INSTALL" | head -1 | cut -d: -f1)"
if [ -n "$src_line" ] && [ -n "$first_rm" ] && [ "$src_line" -lt "$first_rm" ]; then
  ok "recovery-point source (line $src_line) precedes the first rm -rf (line $first_rm)"
else
  bad "recovery-point source (line ${src_line:-?}) does not precede the first rm -rf (line ${first_rm:-?})"
fi

# --- 3. The protect call is guarded on not-a-symlink. `rm -rf` on a link removes
#        the link, never its target, so there is no content at the link path to
#        lose -- and forcing a failure there would change documented behavior,
#        which is why install-opencode.sh skips its archive on the same condition.
if grep -q 'rp_protect' "$INSTALL"; then
  ok "install-hermes.sh protects a path through rp_protect"
else
  bad "install-hermes.sh never calls rp_protect"
fi
if grep -B8 'rp_protect "\$dest"' "$INSTALL" | grep -q '\[ ! -L "\$dest" \]'; then
  ok "rp_protect at the plugin delete site is guarded on not-a-symlink"
else
  bad "rp_protect at the plugin delete site lacks the not-a-symlink guard"
fi

# --- 4. Recovery points are never auto-purged: success leaves the point behind,
#        discarding one is an explicit human rp_discard.
if grep -v '^[[:space:]]*#' "$INSTALL" | grep -q 'rp_discard'; then
  bad "install-hermes.sh discards a recovery point on its own"
else
  ok "install-hermes.sh never auto-discards a recovery point"
fi

# --- 5. The failure path attempts a restore.
if grep -q 'rp_restore' "$INSTALL"; then
  ok "install-hermes.sh restores the recovery point on failure"
else
  bad "install-hermes.sh never calls rp_restore"
fi

# --- 6. Behavioral: a plugin-shaped tree survives delete plus separate-process
#        restore, byte-identically. This mirrors exactly what the installer
#        protects: $CONFIG_DIR/plugins/sefi-commands.
echo "=== plugin directory delete plus separate-process restore ==="
RP_ROOT="$TMP/rp"
PLUGIN="$TMP/plugin-home/plugins/sefi-commands"
mkdir -p "$PLUGIN/nested"
printf '#!/usr/bin/env python3\n# staged sefi-commands entry\n' > "$PLUGIN/__init__.py"
printf 'name: sefi-commands\n' > "$PLUGIN/plugin.yaml"
printf 'command body\n' > "$PLUGIN/nested/init.md"
mkdir -p "$TMP/expected"
cp -R "$PLUGIN" "$TMP/expected/sefi-commands"

point_id="$(SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; id="$(rp_create "hermes-install")"; rp_protect "$2"; printf "%s" "$id"' _ \
  "$HELPER" "$PLUGIN")"
if [ -n "$point_id" ]; then
  ok "rp_create plus rp_protect snapshot the plugin directory ($point_id)"
else
  bad "could not snapshot the plugin directory"
fi

rm -rf "$PLUGIN"
if [ -e "$PLUGIN" ]; then
  bad "test setup: the plugin directory survived the delete"
else
  ok "the destructive step really deleted the plugin directory"
fi

if SEFI_RP_ROOT="$RP_ROOT" bash -c '. "$1"; rp_restore "$2"' _ \
    "$HELPER" "$point_id" >/dev/null 2>&1; then
  ok "a separate process restored the plugin recovery point"
else
  bad "separate-process rp_restore failed"
fi
if diff -r "$TMP/expected/sefi-commands" "$PLUGIN" >/dev/null 2>&1 \
  && cmp -s "$TMP/expected/sefi-commands/__init__.py" "$PLUGIN/__init__.py" \
  && cmp -s "$TMP/expected/sefi-commands/nested/init.md" "$PLUGIN/nested/init.md"; then
  ok "delete plus restore returns byte-identical plugin content, nesting included"
else
  bad "restored plugin content differs from the snapshot"
fi

# --- 7. A clean install-hermes.sh run into a temp Hermes home still returns 0
#        and leaves its recovery point in place.
echo "=== clean stubbed install returns 0, point left in place ==="
. "$CORE/scripts/sefi-python.sh"
if ! PYBIN="$(sefi_python_bin)" || [ -z "$PYBIN" ]; then
  echo "  SKIP: clean-install assertions need Python 3.11+ (CI always has it)"
else
  STUB="$TMP/stubbin"
  HERMES_HOME_FIX="$TMP/hermes-home"
  RP_INSTALL="$TMP/rp-install"
  mkdir -p "$STUB" "$HERMES_HOME_FIX"
  export HERMES_STATE="$HERMES_HOME_FIX"
  export SEFI_SKILLS_SRC="$CORE/skills"
  cat > "$STUB/hermes" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
state="${HERMES_STATE:?}/skills"
case "${1:-}" in
  config) [ "${2:-}" = "path" ] && printf '%s/config.yml\n' "${HERMES_STATE:?}" ;;
  plugins) exit 0 ;;
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
  rc=0
  SEFI_RP_ROOT="$RP_INSTALL" PATH="$STUB:$PATH" bash "$INSTALL" \
    >"$TMP/install.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "clean install-hermes.sh run into a temp Hermes home returns 0"
  else
    bad "clean install-hermes.sh run exited $rc: $(tail -3 "$TMP/install.out")"
  fi
  if [ -f "$HERMES_HOME_FIX/plugins/sefi-commands/__init__.py" ]; then
    ok "clean install stages the sefi-commands plugin directory"
  else
    bad "clean install staged no sefi-commands plugin directory"
  fi
  if SEFI_RP_ROOT="$RP_INSTALL" bash -c '. "$1"; rp_list' _ \
      "$HELPER" 2>/dev/null | grep -q 'hermes-install'; then
    ok "the successful run leaves its recovery point in place (never auto-purged)"
  else
    bad "no hermes-install recovery point survives the successful run"
  fi
fi

# --- 8. A snapshot failure fails closed: no delete, no exit-0 success.
#        Same silent-skip class as the install-opencode.sh archive wiring --
#        the pre-delete rp_protect must abort the run before the rm -rf, and
#        the call site must say so explicitly rather than relying on `set -e`.
echo "=== snapshot failure fails closed (no delete, no success) ==="
if grep -q 'install_commands_plugin || exit 1' "$INSTALL"; then
  ok "the plugin-stage call site aborts explicitly on snapshot failure"
else
  bad "the plugin-stage call site relies on an implicit failure path"
fi
if grep -q 'snapshot failure fails closed' "$INSTALL"; then
  ok "the installer records its snapshot-failure semantics explicitly"
else
  bad "the installer records no explicit snapshot-failure semantics"
fi

if [ -z "${PYBIN:-}" ]; then
  echo "  SKIP: snapshot-failure live assertions need Python 3.11+ (CI always has it)"
else
  FAILSTUB="$TMP/failstubbin"
  FAILHOME="$TMP/fail-hermes-home"
  FAILRP="$TMP/rp-fail"
  mkdir -p "$FAILSTUB" "$FAILHOME/plugins/sefi-commands"
  printf 'operator-owned plugin entry -- must survive a failed install\n' > "$FAILHOME/plugins/sefi-commands/__init__.py"
  printf 'operator-owned command body\n' > "$FAILHOME/plugins/sefi-commands/extra.md"
  export HERMES_STATE="$FAILHOME"
  export SEFI_SKILLS_SRC="$CORE/skills"
  cat > "$FAILSTUB/hermes" <<'FAILHERMESEOF'
#!/usr/bin/env bash
set -uo pipefail
state="${HERMES_STATE:?}/skills"
case "${1:-}" in
  config) [ "${2:-}" = "path" ] && printf '%s/config.yml\n' "${HERMES_STATE:?}" ;;
  plugins) exit 0 ;;
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
FAILHERMESEOF
  chmod +x "$FAILSTUB/hermes"
  # Portable failure injection: fail only the recovery-point snapshot copy
  # (its destination always runs through the point's internal paths/ dir), so
  # every other installer copy -- skills, runtime, plugin staging -- behaves.
  FAIL_CP_REAL="$(command -v cp)"
  cat > "$FAILSTUB/cp" <<FAILCPEOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in */paths/*) exit 1 ;; esac
done
exec "$FAIL_CP_REAL" "\$@"
FAILCPEOF
  chmod +x "$FAILSTUB/cp"
  rc=0
  SEFI_RP_ROOT="$FAILRP" PATH="$FAILSTUB:$PATH" bash "$INSTALL" \
    >"$TMP/install-fail.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "a pre-delete snapshot failure aborts the install (exit $rc, never 0)"
  else
    bad "a pre-delete snapshot failure still exits 0 -- the fail-open is back"
  fi
  if grep -q 'fails closed' "$TMP/install-fail.out"; then
    ok "the abort names its fail-closed semantics"
  else
    bad "the abort recorded no fail-closed diagnostic"
  fi
  if [ "$(cat "$FAILHOME/plugins/sefi-commands/__init__.py" 2>/dev/null)" = "operator-owned plugin entry -- must survive a failed install" ] \
     && [ -f "$FAILHOME/plugins/sefi-commands/extra.md" ]; then
    ok "the unsnapshotted plugin directory was never deleted or replaced (bytes intact)"
  else
    bad "the failed run destroyed or replaced the plugin tree it could not snapshot"
  fi
  if grep -q 'installation succeeded' "$TMP/install-fail.out"; then
    bad "the failed run still printed the success onboarding"
  else
    ok "the failed run printed no success onboarding"
  fi
fi

echo
echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ] || exit 1
exit 0
