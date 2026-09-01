#!/usr/bin/env sh
# check_notes-single-h1.sh -- deterministic acceptance check for benchmark case
# notes-single-h1. Exit 0 = accepted, exit 1 = not accepted. Read-only: no model call,
# no network, no writes. Arg 1 is the trial worktree root (default: current directory).
set -u

root="${1:-.}"
target="$root/benchmarks/sandbox/NOTES.md"

[ -f "$target" ] || { echo "FAIL: $target is missing"; exit 1; }

h1_count=$(grep -c '^# ' "$target" 2>/dev/null || true)
[ -n "$h1_count" ] || h1_count=0

if [ "$h1_count" -ne 1 ]; then
  echo "FAIL: found $h1_count H1 heading(s), want exactly 1"
  exit 1
fi

if ! head -n 1 "$target" | grep -qx '# Release notes'; then
  echo "FAIL: first H1 is not '# Release notes'"
  exit 1
fi

echo "PASS: notes-single-h1"
exit 0
