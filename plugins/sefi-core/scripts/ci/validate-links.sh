#!/usr/bin/env bash
# validate-links.sh -- dead-reference linter: the direction validate-no-orphans.sh cannot
# see. validate-no-orphans walks files ON DISK and asserts each is named in a doc, so a
# reference to a file that does not exist never enters its walk and passes silently. This
# script walks the references IN the docs and asserts each one resolves.
#
# adapters/*.md is deliberately skipped: validate-adapters.sh already owns that direction
# there, and two validators reporting one error is noise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT" || exit 1
CORE="plugins/sefi-core"

errors=0
scanned=0

is_skippable() {
  # Project-scoped paths exist only after /sefi:init inside a user's project, never in this
  # repo. Placeholders are illustrative, not real paths.
  case "$1" in
    config/*|state/*|memory/*|inbox/*|loops/*|.worktrees/*) return 0 ;;
    *YYYY-MM-DD*|*feat-x*) return 0 ;;
    *) return 1 ;;
  esac
}

resolves() {
  # resolves <ref> <referencing-file>
  # All three bases are load-bearing: docs/BUDGET.md resolves at the repo root,
  # scripts/gen-router.sh at the plugin root, and references/roster.md relative to the
  # referencing file's own directory (that is how sefi-orchestration/SKILL.md names its
  # own references).
  local ref="$1" src="$2" dir
  dir="$(dirname "$src")"
  [ -e "$ref" ] && return 0
  [ -e "$CORE/$ref" ] && return 0
  [ -e "$dir/$ref" ] && return 0
  return 1
}

while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanned=$((scanned + 1))
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    is_skippable "$ref" && continue
    if ! resolves "$ref" "$f"; then
      echo "ERROR: $f - references '$ref', which does not resolve"
      errors=$((errors + 1))
    fi
    # URLs are stripped before extraction: a badge link such as
    # github.com/xsefirosus/sefi-agents/actions/workflows/ci.yml otherwise matches as the
    # bogus repo path "agents/actions/workflows/ci.yml".
  done < <(sed 's#https\?://[^ )"]*##g' "$f" \
    | grep -ohE '(docs|skills|scripts|references|templates|agents|commands|plugins|hooks)/[A-Za-z0-9._/-]+\.(md|sh|yml|yaml|json|base|png)' \
    | sort -u)
done < <(git ls-files -- "$CORE/skills" "$CORE/agents" "$CORE/commands" docs README.md Install.md | grep -E '\.md$')

# Bare filenames in prose -- `probe-tools.sh`, not `scripts/probe-tools.sh`. The path regex
# above requires a directory prefix, so a doc naming a script with no path was never
# checked at all. That is the surface README:60 slipped through on for three releases:
# technical-writer.md item 4 ("no feature that is not in the tree") and docs/CHECKLIST.md
# ("back any runtime-behavior claim with a live log line or a probe") both already forbade
# it, and the claim shipped anyway -- which is this repo's own argument for gates over
# prose rules, applied to itself.
bare_errors=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # Resolve anywhere in the tree: docs legitimately name a script without its path.
    if ! find . -name "$name" -not -path './.git/*' -print -quit 2>/dev/null | grep -q .; then
      echo "ERROR: $f - names '$name', which is not a file anywhere in this repo"
      bare_errors=$((bare_errors + 1))
    fi
  done < <(grep -ohE '`[A-Za-z0-9_.-]+\.(sh|yml)`' "$f" 2>/dev/null | tr -d '`' | sort -u)
done < <(git ls-files -- "$CORE/skills" "$CORE/agents" "$CORE/commands" docs README.md Install.md CHANGELOG.md | grep -E '\.md$')
errors=$((errors + bare_errors))

if [ "$errors" -ne 0 ]; then echo "validate-links: $errors error(s)"; exit 1; fi
echo "validate-links: OK ($scanned files scanned, all repo-path references resolve; bare script names checked)"
