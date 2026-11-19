#!/usr/bin/env bash
# test-install-context.sh -- an install must be self-sufficient: the files its scripts
# resolve RELATIVE TO THEMSELVES (harness identity, model map, bundled budget defaults)
# have to land in the destination, or the installed gate falls back to metered and the
# installed model resolver exits 1 with "model map not found".
#
# Covers install.sh and install-opencode.sh against isolated destinations. install-hermes.sh
# writes the same three files through the same shared marker helper; its runtime shipping is
# asserted where a fake hermes CLI already exists (test-systems-audit-installers.sh).
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(cd "$CORE/../.." && pwd)"
INSTALLER="$ROOT/install.sh"
MARKER_HELPER="$CORE/scripts/sefi-harness-marker.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
# The real ccusage would make every spend assertion below measure this machine's ledger
# instead of the fixture's --spent value. Same empty stub technique as test-scripts.sh.
EMPTYBIN="$TMP/emptybin"
mkdir -p "$EMPTYBIN"
printf '#!/bin/sh\nexit 0\n' > "$EMPTYBIN/ccusage"
chmod +x "$EMPTYBIN/ccusage"
stub_path() { env PATH="$EMPTYBIN:$PATH" "$@"; }

echo "=== install context: shared harness-marker helper ==="

bash "$MARKER_HELPER" "$TMP/marker" hermes >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TMP/marker/.sefi/harness" 2>/dev/null)" = "hermes" ] \
  && ok "the marker helper writes one harness name into <root>/.sefi/harness" \
  || bad "the marker helper did not write <root>/.sefi/harness (exit $rc)"
bash "$MARKER_HELPER" "$TMP/marker" hermes >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TMP/marker/.sefi/harness" 2>/dev/null)" = "hermes" ] \
  && ok "a second write of the same name is idempotent (exit 0, one line)" \
  || bad "the marker helper was not idempotent (exit $rc)"
bash "$MARKER_HELPER" "$TMP/marker" claude >/dev/null 2>&1; rc=$?
[ "$(cat "$TMP/marker/.sefi/harness" 2>/dev/null)" = "claude-code" ] \
  && ok "the marker helper normalizes the claude alias to claude-code" \
  || bad "the marker helper did not normalize claude to claude-code (exit $rc)"
bash "$MARKER_HELPER" "$TMP/marker" gold >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown harness name is a usage error (exit 2)" \
  || bad "an unknown harness name was not refused (exit $rc)"
# "never fails the install": a root that cannot hold the marker warns and still exits 0.
printf 'not a directory\n' > "$TMP/blocked"
out="$(bash "$MARKER_HELPER" "$TMP/blocked" hermes 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "an unusable marker directory never fails the install (exit 0)" \
  || bad "an unusable marker directory failed the install (exit $rc)"
case "$out" in
  *"met"*) ok "the unusable marker directory is reported, once, with its consequence" ;;
  *) bad "the unusable marker directory was reported unclearly: $out" ;;
esac

echo
echo "=== install.sh --target cline --copy into an isolated HOME ==="

out="$(cd "$ROOT" && bash "$INSTALLER" --target cline --copy 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "the install exits 0" || bad "the install exited $rc: $out"

CLINE="$HOME/.cline"
[ "$(cat "$CLINE/.sefi/harness" 2>/dev/null)" = "cline" ] \
  && ok "the install writes its own harness name into <dest>/.sefi/harness" \
  || bad "no usable <dest>/.sefi/harness marker after the install"
[ -f "$CLINE/config/model-map.yml" ] \
  && ok "the install ships config/model-map.yml where model-for.sh reads it" \
  || bad "config/model-map.yml was not shipped"
[ -f "$CLINE/scripts/budget-defaults.yml" ] \
  && ok "the install ships scripts/budget-defaults.yml next to the installed script" \
  || bad "scripts/budget-defaults.yml was not shipped"

# The installed resolver, at the path it actually expects: $HERE/../config/model-map.yml.
out="$(bash "$CLINE/scripts/model-for.sh" codex mid 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] \
  && ok "the INSTALLED model-for.sh resolves a tier from the shipped map" \
  || bad "the installed model-for.sh could not resolve its map (exit $rc): $out"

# A check run from an UNRELATED working directory: the install marker resolves the harness
# (cline -> flat, a skip), and the shipped defaults supply the config instead of exit 2.
UNREL="$TMP/unrelated"
mkdir -p "$UNREL"
out="$(cd "$UNREL" && stub_path env -u SEFI_HARNESS bash "$CLINE/scripts/budget-check.sh" --scope daily --spent 999.00 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "the install marker resolves cline (flat) from an unrelated cwd" \
  || bad "the install marker did not resolve the harness from an unrelated cwd (exit $rc): $out"
case "$out" in
  *"billing_mode=flat"*) ok "the marker-resolved skip records the harness default it used" ;;
  *) bad "the marker-resolved skip named no mode: $out" ;;
esac
case "$out" in
  *"not found"*) bad "the shipped defaults were not found from an unrelated cwd: $out" ;;
  *) ok "the shipped defaults are found from an unrelated cwd (no 'config not found')" ;;
esac

# Non-vacuous counter-case: the SAME scripts and defaults with the install marker removed
# resolve no harness at all and must enforce, fail-closed. That is the gate the marker,
# and only the marker, turns into a skip.
cp -R "$CLINE/scripts" "$TMP/nomarker-scripts"
mkdir -p "$TMP/nomarker"
mv "$TMP/nomarker-scripts" "$TMP/nomarker/scripts"
out="$(cd "$UNREL" && stub_path env -u SEFI_HARNESS bash "$TMP/nomarker/scripts/budget-check.sh" --scope daily --spent 999.00 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "without the install marker the same install stays metered (enforces)" \
  || bad "without the install marker the install did not stay metered (exit $rc): $out"

echo
echo "=== install-opencode.sh into an isolated OPENCODE_HOME ==="

OC="$HOME/.config/opencode"
out="$(OPENCODE_HOME="$OC" bash "$CORE/scripts/install-opencode.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "install-opencode.sh exits 0" || bad "install-opencode.sh exited $rc: $out"
[ "$(cat "$OC/.sefi/harness" 2>/dev/null)" = "opencode" ] \
  && ok "the OpenCode install records its own harness name" \
  || bad "no usable OpenCode harness marker"
[ -f "$OC/config/model-map.yml" ] \
  && ok "the OpenCode install ships config/model-map.yml" \
  || bad "the OpenCode install shipped no model map"
[ -f "$OC/scripts/budget-defaults.yml" ] \
  && ok "the OpenCode install ships scripts/budget-defaults.yml" \
  || bad "the OpenCode install shipped no budget defaults"
out="$(bash "$OC/scripts/model-for.sh" codex high 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] \
  && ok "the INSTALLED OpenCode model-for.sh resolves a tier from the shipped map" \
  || bad "the installed OpenCode model-for.sh could not resolve its map (exit $rc): $out"
# --auto-update on an unchanged install exits early ("nothing to do"); the context files
# must already be in place from the install above, which is why they are written before
# that gate rather than after it.
[ -f "$OC/config/model-map.yml" ] && [ -f "$OC/scripts/budget-defaults.yml" ] \
  && ok "an existing install keeps its context files (written before the auto-update gate)" \
  || bad "an existing install lost its context files"

# The context files are destination-only: the package manifest is built from SOURCE files
# and never compares the other direction, so shipping them must leave the manifest verdict
# at "current". If it flipped to drift, every later --auto-update would refuse the install.
for pair in "opencode:$OC" "cline:$CLINE"; do
  label="${pair%%:*}"
  dest="${pair#*:}"
  manifest_out="$(bash "$CORE/scripts/package-manifest.sh" diff --root "$dest" --source "$CORE/scripts" --destination "$dest/scripts" 2>&1)" || true
  case "$manifest_out" in
    *"package-manifest-diff: current"*) ok "the shipped context files keep the $label manifest current (no drift)" ;;
    *) bad "the shipped context files changed the $label manifest verdict: $manifest_out" ;;
  esac
done

echo
if [ "$fail" -ne 0 ]; then echo "test-install-context: $fail failed, $pass passed"; exit 1; fi
echo "test-install-context: OK ($pass passed)"
