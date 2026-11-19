#!/usr/bin/env bash
# validate-skill-doc-refs.sh -- a skill's own relative documentation pointers must resolve
# INSIDE that skill's directory.
#
# Why this exists: an installed bundle ships a skill's SKILL.md but not the repository's
# docs/ tree, so a bare pointer to `docs/BUDGET.md` is dangling in every install. The
# repo-wide link validator (validate-links.sh) resolves the same path against the REPOSITORY
# root and reports nothing, because there the file exists -- the two contexts disagree, and
# only the repository one was ever checked. This validator checks the context the reader
# actually gets.
#
# Contract:
#   * a standalone relative path into docs/ or references/ is resolved against the
#     referencing skill's directory and must exist there as a file, with no parent-directory
#     escape;
#   * a path prefixed with `repo:` is a REPOSITORY-ONLY reference (docs/BUDGET.md lives at
#     the repo root and is never copied into a skill) and is exempt by contract;
#   * a path already spelled with a skill prefix (skills/<name>/references/<file>.md) points
#     at ANOTHER skill's file, not this one's, and is not matched at all. That distinction is
#     the reason the match is anchored on a preceding non-path character: without it every
#     cross-skill pointer would be misread as a dangling pointer into the referencing skill.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILLS="$ROOT/plugins/sefi-core/skills"

extract_refs() {
  # extract_refs <file> -- print each standalone relative documentation/reference path the
  # file names, one per line, deduplicated. `repo:`-prefixed paths are blanked first (they
  # are exempt), and the match requires a non-path character in front, so a cross-skill
  # `skills/.../references/x.md` pointer is never extracted as `references/x.md`.
  sed 's#repo:[A-Za-z0-9._/-]*##g' "$1" \
    | grep -ohE '(^|[^A-Za-z0-9._/-])(docs|references)/[A-Za-z0-9._/-]+\.(md|sh|yml|yaml|json)' \
    | sed -E 's#^[^A-Za-z0-9._/-]*(docs|references)/#\1/#' \
    | sort -u
}

errors=0
scanned=0

for dir in "$SKILLS"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  file="${dir}SKILL.md"
  if [ ! -f "$file" ]; then
    echo "ERROR: skills/$name has no SKILL.md"
    errors=$((errors + 1))
    continue
  fi
  scanned=$((scanned + 1))
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      *..*)
        echo "ERROR: $file - references '$ref', which walks out of the skill directory; spell a repository-only path with a 'repo:' prefix"
        errors=$((errors + 1))
        continue
        ;;
    esac
    if [ ! -f "$dir$ref" ]; then
      echo "ERROR: $file - references '$ref', which does not exist inside skills/$name (a skill ships no repository docs/ tree; spell a repository-only reference as 'repo:<path>')"
      errors=$((errors + 1))
    fi
  done < <(extract_refs "$file")
done

if [ "$errors" -ne 0 ]; then
  echo "validate-skill-doc-refs: $errors error(s)"
  exit 1
fi
echo "validate-skill-doc-refs: OK ($scanned skills, every relative doc reference resolves)"
