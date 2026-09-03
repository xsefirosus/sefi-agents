#!/usr/bin/env bash
# validate-rule-presence.sh -- content-presence contract test. Asserts that every
# load-bearing rule sentence listed in scripts/ci/rule-presence.manifest is still
# physically present in the file that owns it. Catches the failure shape a link or
# structure linter cannot: a rule silently deleted, gutted, or reworded past
# recognition while every path still resolves and every heading still parses.
#
# Normalization (applied to the target file PARAGRAPH-LOCALLY, and to the registered
# sentence as a single line):
#   Split the target file into paragraphs on paragraph breaks -- a paragraph break is
#   any line with no non-whitespace content (truly empty, OR only spaces/tabs; Markdown
#   treats both the same). Within one paragraph, collapse every whitespace run --
#   soft-wrap newlines included -- to a single space, trim, then drop a single trailing
#   '.' or ':'. Paragraph breaks are NOT bridged, so a sentence broken by an inserted
#   paragraph break no longer matches. Case-sensitive otherwise. A row PASSES when its
#   normalized sentence is a substring of some normalized paragraph of the target file.
#
# Usage:
#   validate-rule-presence.sh [--manifest <path>] [--base <dir>] [--strict]
#   validate-rule-presence.sh --post-install <DEST>
#
#   --manifest <path>   manifest file to read (default: the sibling rule-presence.manifest)
#   --base <dir>        directory the manifest's repo-relative paths resolve against
#                       (default: repo root)
#   --post-install <DEST>  cross-harness survival mode. Resolve each manifest path with
#                       its leading 'plugins/sefi-core/' stripped, against <DEST> -- the
#                       tree install-opencode.sh writes. Proves every registered sentence
#                       survives the one install transform that rewrites files.
#   --strict            accepted and ignored, for parity with the sibling validators
#                       run-all.sh forwards --strict to (this check has no warning tier).
#
# Exit: 0 all sentences present; 1 a miss, a missing target file, an empty manifest, an
# unknown argument, or an option given without its required value.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
MANIFEST="$(cd "$(dirname "$0")" && pwd)/rule-presence.manifest"
BASE="$ROOT"
STRIP=""

# Each value-taking option consumes exactly one following argument. Guard every such
# consumption: a bare '--manifest' at end of line is a setup error (exit 1), never a
# silent spin -- 'set -u' without '-e' means a failed 'shift 2' would otherwise leave
# the flag unconsumed and the loop below never terminating.
need_val() {
  # need_val <flag> <remaining-arg-count>
  [ "$2" -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) shift ;;
    --manifest)     need_val "$1" "$#"; MANIFEST="$2"; shift 2 ;;
    --base)         need_val "$1" "$#"; BASE="$2"; shift 2 ;;
    --post-install) need_val "$1" "$#"; BASE="$2"; STRIP="plugins/sefi-core/"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$MANIFEST" ] && [ -f "$MANIFEST" ] || {
  echo "ERROR: $MANIFEST - manifest file not found"; exit 1;
}
[ -n "$BASE" ] && [ -d "$BASE" ] || {
  echo "ERROR: $BASE - base directory not found"; exit 1;
}

# Data rows only: strip comments and blank lines.
rows="$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")"
[ -n "$rows" ] || { echo "ERROR: $MANIFEST - manifest is empty (no registered sentences)"; exit 1; }

normalize_line() {
  # stdin (one logical sentence) -> one normalized line on stdout
  tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//; s/[.:]$//; s/ *$//'
}

normalize_file() {
  # $1 = path. Emits one normalized line PER PARAGRAPH (blank-line-delimited block):
  # within a paragraph, whitespace runs -- soft-wrap newlines included -- collapse to a
  # single space; trim; drop one trailing '.'/':'. Paragraph breaks are never bridged.
  #
  # The leading sed blanks any line that is whitespace-only (a lone space or tab, a run
  # of them, trailing CR). Markdown treats such a line as a paragraph break, but awk's
  # RS="" paragraph mode splits ONLY on truly empty lines -- without this a separator
  # holding a single space or tab would silently join two paragraphs and let a sentence
  # that straddles it match.
  sed 's/[[:space:]]*$//' "$1" | awk 'BEGIN { RS = ""; ORS = "\n" }
       {
         gsub(/[[:space:]]+/, " ")
         sub(/^ +/, ""); sub(/ +$/, "")
         sub(/[.:]$/, "")
         print
       }'
}

errors=0
n=0
files_seen=" "
tab="$(printf '\t')"

while IFS="$tab" read -r file sentence || [ -n "$file" ]; do
  [ -n "$file" ] || continue
  case "$file" in \#*) continue ;; esac
  if [ -z "$sentence" ]; then
    echo "ERROR: $file - manifest row carries no rule sentence (missing tab?)"
    errors=$((errors + 1)); continue
  fi

  target="$file"
  if [ -n "$STRIP" ]; then
    # --post-install resolves rows against the tree install-opencode.sh writes, which
    # only contains what lived under "$STRIP". A row outside that prefix cannot be
    # resolved there; fail it by name rather than silently misresolving to $BASE/$file
    # and reporting a generic "target file not found" (see rule-presence.manifest header).
    case "$file" in
      "$STRIP"*) target="${file#"$STRIP"}" ;;
      *)
        echo "ERROR: $file - row path is outside '$STRIP'; --post-install can only resolve paths under that prefix"
        errors=$((errors + 1)); continue ;;
    esac
  fi
  path="$BASE/$target"

  if [ ! -f "$path" ]; then
    echo "ERROR: $file - target file not found ($path)"
    errors=$((errors + 1)); continue
  fi

  norm_sentence="$(printf '%s\n' "$sentence" | normalize_line)"
  if normalize_file "$path" | awk -v s="$norm_sentence" 'index($0, s) { hit = 1 } END { exit(hit ? 0 : 1) }'; then
    n=$((n + 1))
    case "$files_seen" in *" $file "*) : ;; *) files_seen="$files_seen$file " ;; esac
  else
    echo "ERROR: $file - missing registered rule sentence: $sentence"
    errors=$((errors + 1))
  fi
done <<EOF
$rows
EOF

m="$(printf '%s' "$files_seen" | wc -w | tr -d ' ')"

if [ "$errors" -ne 0 ]; then
  echo "validate-rule-presence: $errors error(s)"
  exit 1
fi
echo "validate-rule-presence: OK ($n sentences across $m files)"
