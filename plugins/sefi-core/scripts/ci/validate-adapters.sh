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

errors=0

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

if [ "$errors" -ne 0 ]; then echo "validate-adapters: $errors error(s)"; exit 1; fi
echo "validate-adapters: OK (install-hermes.sh skill list matches disk, adapter doc paths resolve)"
