#!/usr/bin/env bash
# validate-adapters.sh -- doc-consistency linter for the harness-neutral claim. Checks
# that install-hermes.sh's hardcoded skill list matches the actual skills on disk
# (both directions -- a drift either way means a skill silently never installs, or the
# script references one that no longer exists), and that adapter docs under adapters/
# don't reference a plugins/sefi-core/... repo path that no longer exists. NOT a
# live-harness test: it cannot verify a harness actually runs the plugin, only that the
# adapter docs and install list do not reference things that have drifted or vanished.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
INSTALL_HERMES="$CORE/scripts/install-hermes.sh"
CODEX_PLUGIN="$CORE/.codex-plugin/plugin.json"
CODEX_MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"
MANIFEST_DIR="$ROOT/adapters/manifests"
MANIFEST_HELPER="$CORE/scripts/adapter-manifest.sh"

errors=0

# Adapter manifests are the stable installer contract. A shipped manifest is verified;
# custom/local manifests are accepted only through install.sh --adapter and never listed
# here as supported harnesses.
[ -f "$MANIFEST_HELPER" ] || { echo "ERROR: adapter manifest driver is missing: $MANIFEST_HELPER"; exit 1; }
# shellcheck source=plugins/sefi-core/scripts/adapter-manifest.sh
source "$MANIFEST_HELPER"
for id in claude-code codex opencode hermes; do
  manifest="$MANIFEST_DIR/$id.yml"
  if ! adapter_manifest_load "$manifest"; then
    echo "ERROR: invalid shipped adapter manifest: $manifest"
    errors=$((errors + 1))
  elif [ "$ADAPTER_ID" != "$id" ] || [ "$ADAPTER_VERIFICATION" != "verified" ] || [ "$ADAPTER_SUPPORT" != "shipped" ]; then
    echo "ERROR: shipped adapter manifest has inconsistent id/support status: $manifest"
    errors=$((errors + 1))
  fi
done

# 1. install-hermes.sh's SKILLS= list vs actual skill directories, both directions.
listed="$(grep '^SKILLS=' "$INSTALL_HERMES" | sed -E 's/^SKILLS="(.*)"$/\1/' | tr ' ' '\n' | sort)"
on_disk="$(find "$CORE/skills" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)"

while IFS= read -r name; do
  [ -z "$name" ] && continue
  if [ ! -d "$CORE/skills/$name" ]; then
    echo "ERROR: install-hermes.sh lists skill '$name' with no skills/$name/ directory"
    errors=$((errors + 1))
  fi
done <<< "$listed"

while IFS= read -r name; do
  [ -z "$name" ] && continue
  if ! printf '%s\n' "$listed" | grep -qxF "$name"; then
    echo "ERROR: skills/$name/ exists on disk but is not in install-hermes.sh's SKILLS list"
    errors=$((errors + 1))
  fi
done <<< "$on_disk"

# 2. Every plugins/sefi-core/... repo-path reference in adapters/*.md must exist.
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  if [ ! -e "$ROOT/$ref" ]; then
    echo "ERROR: an adapters/*.md doc references '$ref', which does not exist"
    errors=$((errors + 1))
  fi
done < <(grep -ohE 'plugins/sefi-core/[A-Za-z0-9._/-]+' "$ROOT"/adapters/*.md | sort -u)

# 3. Codex has a native package path. Keep its manifest version synchronized with the
# Claude-compatible source of record, and make sure the native marketplace reaches it.
claude_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$CORE/.claude-plugin/plugin.json" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
codex_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$CODEX_PLUGIN" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
if [ ! -f "$CODEX_PLUGIN" ]; then
  echo "ERROR: native Codex plugin manifest is missing: $CODEX_PLUGIN"
  errors=$((errors + 1))
elif [ -z "$codex_version" ] || [ "$codex_version" != "$claude_version" ]; then
  echo "ERROR: native Codex plugin version '$codex_version' does not match Claude manifest '$claude_version'"
  errors=$((errors + 1))
fi

if [ ! -f "$CODEX_MARKETPLACE" ]; then
  echo "ERROR: native Codex marketplace manifest is missing: $CODEX_MARKETPLACE"
  errors=$((errors + 1))
elif ! grep -qF '"source": "local"' "$CODEX_MARKETPLACE" \
  || ! grep -qF '"path": "./plugins/sefi-core"' "$CODEX_MARKETPLACE"; then
  echo "ERROR: native Codex marketplace does not point to ./plugins/sefi-core"
  errors=$((errors + 1))
fi

if [ ! -f "$ROOT/install-codex.sh" ]; then
  echo "ERROR: Codex bootstrap installer is missing: $ROOT/install-codex.sh"
  errors=$((errors + 1))
fi

if [ "$errors" -ne 0 ]; then echo "validate-adapters: $errors error(s)"; exit 1; fi
echo "validate-adapters: OK (installers, native Codex package, and adapter doc paths resolve)"
