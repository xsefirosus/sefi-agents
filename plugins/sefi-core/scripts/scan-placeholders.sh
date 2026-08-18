#!/usr/bin/env bash
# scan-placeholders.sh <file>   (or: ... | scan-placeholders.sh -)
#
# Deterministic post-hoc scan for hallucination/placeholder patterns the writing-side
# anti-hallucination discipline still lets through: a stray "probably works", an unedited
# TODO:, a copy-pasted lorem ipsum, an unfilled your_api_key_here template. Evidence for the
# qa-engineer to judge, not an automatic verdict -- same relationship check-bar.sh has to
# the bar-comparison evidence type.
#
# Four categories only. A fifth source category, code_generation (matching def/class/
# import/fenced-code-blocks), is deliberately excluded: check-reply.sh's foreign-deliverable
# check (its check 3) already catches a full document leak -- HTML, a plan skeleton -- from
# a read-only agent, which is the failure shape code_generation was trying to catch more
# crudely. If check-reply.sh's foreign-deliverable check is ever narrowed, re-verify this
# exclusion before assuming it still holds.
#
# ALWAYS EXITS 0. This is evidence collection, not a pass/fail gate -- a hit is a prompt to
# look, never an automatic REJECT. A caller that treats a clean exit code as "no hits" is
# using this wrong: read the CATEGORY lines on stderr, the hit count is the signal, not the
# exit code. (Contrast check-bar.sh / check-reply.sh, which DO gate on exit code -- this
# script's job is different by design, not by oversight.)
set -uo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "scan-placeholders: usage: scan-placeholders.sh <file>|-" >&2; exit 0; }

if [ "$SRC" = "-" ]; then
  TXT="$(cat)"
else
  if [ ! -f "$SRC" ]; then
    echo "scan-placeholders: $SRC not found" >&2
    exit 0
  fi
  TXT="$(cat "$SRC")"
fi

total=0

scan_category() {
  # scan_category <label> <pattern...> -- each remaining arg is one case pattern; a line
  # matching ANY of them counts toward this category's hit count. Patterns are matched
  # case-insensitively against each line of $TXT independently, so a count reflects lines
  # hit, not just presence.
  local label="$1"; shift
  local hits=0
  local matched=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local low
    low="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    for pat in "$@"; do
      # shellcheck disable=SC2254
      case "$low" in
        $pat)
          hits=$((hits + 1))
          matched="${matched}${line}"$'\n'
          break
          ;;
      esac
    done
  done <<< "$TXT"
  if [ "$hits" -gt 0 ]; then
    total=$((total + hits))
    echo "$label: $hits hit(s)" >&2
    printf '%s' "$matched" | sed 's/^/  > /' >&2
  fi
}

# uncertain_language: a hedge attached to a factual claim, not a hedge explaining a hedge.
scan_category "uncertain_language" \
  "*i believe that*" "*i think that*" "*i assume that*" "*i guess that*" \
  "*probably works*" "*likely works*" "*possibly works*" "*maybe works*"

# incomplete_implementation: an unresolved marker left in place.
scan_category "incomplete_implementation" \
  "*todo: implement*" "*todo: add*" "*todo: fix*" "*todo: create*" \
  "*fixme:*" "*hack:*"

# placeholder_content: unfilled template material.
scan_category "placeholder_content" \
  "*placeholder*" "*lorem ipsum*" "*xxx*" "*aaa*" "*zzz*" "*your_*_here*"

# test_urls: a fixture/example address left in real output.
scan_category "test_urls" \
  "*http://example.com*" "*https://example.com*" \
  "*http://localhost*" "*https://localhost*" \
  "*http://127.0.0.1*" "*https://127.0.0.1*"

echo "scan-placeholders: $total total hit(s) across 4 categories (evidence only -- always exits 0)" >&2
exit 0
