#!/usr/bin/env sh
# check_json-trailing-newline.sh -- deterministic acceptance check for benchmark case
# json-trailing-newline. Exit 0 = accepted, exit 1 = not accepted. Read-only: no model
# call, no network, no writes. Arg 1 is the trial worktree root (default: current dir).
set -u

root="${1:-.}"
target="$root/benchmarks/sandbox/config.json"

[ -f "$target" ] || { echo "FAIL: $target is missing"; exit 1; }
[ -s "$target" ] || { echo "FAIL: $target is empty"; exit 1; }

first_char=$(head -c 1 "$target")
if [ "$first_char" != "{" ]; then
  echo "FAIL: file does not begin with '{'"
  exit 1
fi

# Command substitution strips trailing newlines: a non-empty result means the last byte
# is not a newline, i.e. no trailing newline.
last_byte=$(tail -c 1 "$target")
if [ -n "$last_byte" ]; then
  echo "FAIL: file does not end with exactly one newline"
  exit 1
fi

if ! grep -Eq '^  +"' "$target"; then
  echo "FAIL: no 2-space-indented line found (not pretty-printed)"
  exit 1
fi

echo "PASS: json-trailing-newline"
exit 0
