#!/usr/bin/env bash
# validate-comment-safety.sh -- a literal "--" inside an XML/HTML comment body is illegal
# XML and silently breaks the whole document's parse. Live-hit in 0.3.27: this repo's own
# em-dash convention ("--" in place of an em-dash) landed inside a comment in
# docs/assets/how-it-works.svg, and the entire diagram rendered blank via <img> with no
# error anywhere -- only caught by pixel-scanning the actual screenshot, not by reading the
# markup. The house style using "--" everywhere makes this a systemic collision, not a
# one-off: any doc comment in any *.svg or *.html file is one edit away from repeating it.
#
# Scans tracked *.svg and *.html files. A "--" is only illegal inside the comment BODY --
# the closing "-->" delimiter itself is fine and never flagged.
#
# Implemented in awk with RS="-->" (splits the file into records at each comment close),
# not a line-based read loop: an earlier draft of this exact script read each ripgrep
# match with `read -r`, which silently truncates at the first embedded newline -- meaning
# it would NOT have caught the real multi-line comment that motivated writing it. Caught
# by testing the draft against a synthetic multi-line fixture before shipping it, not
# assumed correct from reading the script.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT" || exit 1

AWK_PROG='
BEGIN { RS = "-->" }
{
  rec = $0
  idx = -1
  pos = 1
  while (1) {
    p = index(substr(rec, pos), "<!--")
    if (p == 0) break
    idx = pos + p - 1
    pos = idx + 4
  }
  if (idx > 0) {
    body = substr(rec, idx + 4)
    if (index(body, "--") > 0) {
      gsub(/\n/, " ", body)
      snippet = substr(body, 1, 70)
      printf "ERR\t%s - comment body contains a double-dash, illegal XML (silently breaks the parse): %s...\n", FILENAME, snippet
    }
  }
}
'

errors=0
scanned=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanned=$((scanned + 1))
  while IFS=$'\t' read -r tag msg; do
    [ "$tag" = "ERR" ] || continue
    echo "ERROR: $msg"
    errors=$((errors + 1))
  done < <(awk "$AWK_PROG" "$f")
done < <(git ls-files -- '*.svg' '*.html')

if [ "$errors" -ne 0 ]; then echo "validate-comment-safety: $errors error(s)"; exit 1; fi
echo "validate-comment-safety: OK ($scanned file(s) scanned)"
