#!/usr/bin/env bash
# validate-config-wired.sh -- inert-config linter. Every key declared in
# templates/config/*.yml must be READ by a script or NAMED as a rule in a skill, command,
# agent, or doc. A key's presence in a validator's required-list does NOT count as wiring:
# that circularity is exactly what hid per_agent_return_tokens (its only reference was
# validate-budget.sh asserting the key exists).
#
# Searches git-tracked files only. This is load-bearing, not incidental: a gitignored local
# doc can make a key look wired on a developer's disk while the shipped artifact has it
# orphaned. loops.never_auto_merge was in exactly that state -- referenced only from a
# gitignored master-prompt draft.
#
# Nested keys are checked by dotted path (memory.vault_dir), so whatever wires a key must
# name it by its full config path. Flat keys (budget.yml) are checked bare.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT" || exit 1
CORE="plugins/sefi-core"

errors=0
checked=0

# A wiring claim may not come from the templates themselves, nor from a validator whose
# only job is asserting a key is present.
EXCLUDES=(
  ":!$CORE/templates/config"
  ":!$CORE/scripts/ci/validate-budget.sh"
  ":!$CORE/scripts/ci/validate-config-wired.sh"
)

for cfg in "$CORE"/templates/config/*.yml; do
  [ -f "$cfg" ] || continue
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    checked=$((checked + 1))
    if git grep -qF "$key" -- "${EXCLUDES[@]}" >/dev/null 2>&1; then
      :
    else
      echo "ERROR: $cfg - key '$key' is declared but never read by a script or named as a rule"
      errors=$((errors + 1))
    fi
  done < <(awk '
    /^[[:space:]]*#/            { next }
    /^[a-z_][a-z_0-9]*:[[:space:]]*$/ { parent=$1; sub(/:$/,"",parent); next }
    /^[a-z_][a-z_0-9]*:[[:space:]]+[^[:space:]]/ { k=$1; sub(/:$/,"",k); print k; parent=""; next }
    /^[[:space:]]+[a-z_][a-z_0-9]*:[[:space:]]+[^[:space:]]/ {
      k=$1; sub(/:$/,"",k)
      if (parent != "") print parent "." k; else print k
      next
    }
  ' "$cfg")
done

if [ "$errors" -ne 0 ]; then echo "validate-config-wired: $errors error(s)"; exit 1; fi
echo "validate-config-wired: OK ($checked config keys, all wired)"
