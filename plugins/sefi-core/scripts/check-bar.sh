#!/usr/bin/env bash
# check-bar.sh <envelope-file>   (or: ... | check-bar.sh -)
#
# Deterministic gate on a bar-comparison envelope (skills/anti-hallucination/references/
# bar-comparison.md): the Named / Fetchable / Comparable test, applied before a qa-engineer
# verdict may cite a side-by-side against a real external artifact, so an unreachable or
# vague "bar" can never become a hallucinated comparison.
#
# Envelope format (one field per line, `key: value`):
#   bar:     <the named artifact being compared against -- a real thing, not a category>
#   source:  <a local path or an http(s) URL where the bar can be inspected>
#   compare: <what dimension is being compared>
#
# NAMED (bar:): rejects a vague category label from a denylist (award-winning,
# best-in-class, industry-leading, modern, professional, top-tier) -- "award-winning SaaS
# sites" names a category, not a bar; "Linear's issue list" names one.
#
# FETCHABLE (source:): must resolve as an existing local path, or parse as an http(s) URL.
# URL REACHABILITY IS NOT VERIFIED -- the plugin makes no network calls, so this checks
# syntax only. Claiming a full reachability check here would be exactly the overclaim this
# gate exists to prevent; a local path IS checked for real, since that costs nothing.
#
# COMPARABLE (compare:): must be non-empty -- name the dimension, not "it's better".
#
# Exit 0 when the envelope passes all three; 1 when it does not; 2 on a usage error.
set -uo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "check-bar: usage: check-bar.sh <envelope-file>|-" >&2; exit 2; }

if [ "$SRC" = "-" ]; then
  ENV_TXT="$(cat)"
else
  [ -f "$SRC" ] || { echo "check-bar: $SRC not found" >&2; exit 2; }
  ENV_TXT="$(cat "$SRC")"
fi

errors=0
field() { printf '%s\n' "$ENV_TXT" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }
err()   { echo "ERROR: $1"; errors=$((errors + 1)); }

for key in bar source compare; do
  printf '%s\n' "$ENV_TXT" | grep -qE "^$key:" || err "missing required field '$key:'"
done

BAR="$(field bar)"
SOURCE="$(field source)"
COMPARE="$(field compare)"

# 1. NAMED: a real artifact, not a category label. Category words drift upward exactly
# like an unbound comparison score -- "award-winning" describes nothing checkable.
if [ -z "$BAR" ]; then
  err "'bar:' is empty -- name the specific artifact, e.g. 'Linear's issue list view'"
else
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    if printf '%s' "$BAR" | grep -qiF "$label"; then
      err "'bar: $BAR' names a category ('$label'), not a specific artifact -- Named requires a real thing to compare against"
    fi
  done <<'DENYLIST'
award-winning
best-in-class
industry-leading
modern
professional
top-tier
DENYLIST
fi

# 2. FETCHABLE: an existing local path, or a syntactically valid http(s) URL. Reachability
# of a URL is never checked -- the plugin makes no network calls, and claiming otherwise
# would be the overclaim this gate exists to prevent.
case "$SOURCE" in
  '') err "'source:' is empty -- give a local path or an http(s) URL" ;;
  http://*|https://*) : ;;
  *)
    [ -e "$SOURCE" ] || err "'source: $SOURCE' does not exist as a local path and is not an http(s) URL" ;;
esac

# 3. COMPARABLE: a stated dimension, not a vibe.
[ -n "$COMPARE" ] || err "'compare:' is empty -- name the dimension being compared, not just 'it's better'"

if [ "$errors" -ne 0 ]; then
  echo "check-bar: $errors problem(s) -- bar envelope rejected"
  exit 1
fi
echo "check-bar: OK (bar='$BAR' source=$SOURCE)"
exit 0
