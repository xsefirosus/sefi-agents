#!/usr/bin/env bash
# CI: the cline adapter installs, validates, and is idempotent.
#
# Cline is the fifth shipped harness. Its manifest is verification:verified /
# support:shipped, so --adapter (which accepts ONLY locally usable custom
# manifests) must reject it and the real path is `install.sh --target cline`.
# These cases pin that, pin the manifest contract fields that distinguish cline
# from the other four harnesses (subagent delegation, flexible model, headless
# unknown, ${HOME}/.cline destination), and pin that a real install into an
# isolated HOME lays agents/skills/commands/scripts and is idempotent.
#
# The install runs against an isolated HOME under a temp dir, never the
# operator's real ~/.cline.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(cd "$CORE/../.." && pwd)"
INSTALLER="$ROOT/install.sh"
MANIFEST="$ROOT/adapters/manifests/cline.yml"
MANIFEST_HELPER="$CORE/scripts/adapter-manifest.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "=== cline adapter: manifest contract ==="

[ -f "$MANIFEST" ] || { bad "cline manifest missing"; echo "  (0 passed, 1 failed)"; exit 1; }

# Load the manifest through the shared parser and assert the fields that define cline.
(
  # shellcheck source=/dev/null
  . "$MANIFEST_HELPER"
  adapter_manifest_load "$MANIFEST" || exit 9
  [ "$ADAPTER_VERIFICATION" = "verified" ] || { echo "verification=$ADAPTER_VERIFICATION"; exit 1; }
  [ "$ADAPTER_SUPPORT" = "shipped" ]    || { echo "support=$ADAPTER_SUPPORT"; exit 1; }
  [ "$ADAPTER_ID" = "cline" ]           || { echo "id=$ADAPTER_ID"; exit 1; }
  [ "$ADAPTER_DELEGATION" = "subagent" ]    || { echo "delegation=$ADAPTER_DELEGATION"; exit 1; }
  [ "$ADAPTER_MODEL_STRATEGY" = "flexible" ] || { echo "model_strategy=$ADAPTER_MODEL_STRATEGY"; exit 1; }
  [ "$ADAPTER_HEADLESS" = "unknown" ]       || { echo "headless=$ADAPTER_HEADLESS"; exit 1; }
  [ "$ADAPTER_DESTINATION" = '${HOME}/.cline' ] || { echo "destination=$ADAPTER_DESTINATION"; exit 1; }
  exit 0
)
rc=$?
[ "$rc" -eq 0 ] && ok "cline manifest loads and pins verified/shipped/subagent/flexible/unknown/.cline" \
  || bad "cline manifest contract fields wrong (rc=$rc)"

echo
echo "=== cline adapter: --adapter rejects a shipped manifest ==="
# verification:verified means --adapter (custom-only) must refuse it.
out="$(bash "$INSTALLER" --adapter "$MANIFEST" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "--adapter rejects the shipped cline manifest (exit 2)" \
  || bad "--adapter did not reject the shipped cline manifest (exit $rc): $out"
case "$out" in
  *custom*) ok "rejection names the custom-only contract" ;;
  *) bad "rejection message unclear: $out" ;;
esac

echo
echo "=== cline adapter: install into an isolated HOME (copy mode) ==="
# Copy mode is the documented cline path (adapters/CLINE.md section 2): symlink mode
# cannot rewrite the plugin-root placeholder in file content without mutating the
# source checkout, and the package manifest is written only for copied scripts/.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

out="$(cd "$ROOT" && bash "$INSTALLER" --target cline --copy 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "install.sh --target cline --copy exits 0" \
  || bad "install.sh --target cline --copy exited $rc: $out"

for d in agents skills commands scripts; do
  [ -d "$HOME/.cline/$d" ] && ok "installed $d/ under \$HOME/.cline" \
    || bad "no $d/ under \$HOME/.cline after install"
done
[ -f "$HOME/.cline/agents/sefi-agents.md" ] && ok "installed the coordinator agent body" \
  || bad "coordinator agent body missing after install"
[ -f "$HOME/.cline/scripts/.sefi-agents-manifest.json" ] && ok "scripts/ carries the package manifest" \
  || bad "scripts/ package manifest missing after install"
# No unreplaced plugin-root placeholder anywhere in the installed agents.
if grep -rl 'CLAUDE_PLUGIN_ROOT' "$HOME/.cline/agents" >/dev/null 2>&1; then
  bad "installed agents still contain the \${CLAUDE_PLUGIN_ROOT} placeholder"
else
  ok "installed agents have no \${CLAUDE_PLUGIN_ROOT} placeholder"
fi

echo
echo "=== cline adapter: second run without --force refuses (no overwrite) ==="
# install.sh refuses to overwrite without --force (header contract); a refused
# second run must exit nonzero and leave the installed tree intact.
out2="$(cd "$ROOT" && bash "$INSTALLER" --target cline --copy 2>&1)"; rc2=$?
[ "$rc2" -ne 0 ] && ok "second install without --force refuses (exit $rc2)" \
  || bad "second install without --force unexpectedly succeeded"
case "$out2" in
  *"use --force"*) ok "refusal names the --force remedy" ;;
  *) bad "refusal message unclear: $out2" ;;
esac
[ -f "$HOME/.cline/agents/sefi-agents.md" ] && ok "coordinator body still present after second run" \
  || bad "coordinator body missing after second run"

echo
if [ "$fail" -ne 0 ]; then echo "test-install-cline-adapter: $fail failed, $pass passed"; exit 1; fi
echo "test-install-cline-adapter: OK ($pass passed)"
