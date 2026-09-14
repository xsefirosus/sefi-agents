#!/usr/bin/env sh
# check_sh-strict-mode.sh -- deterministic acceptance check for benchmark case
# sh-strict-mode. Exit 0 = accepted, exit 1 = not accepted. Read-only: no model call,
# no network, no writes. Arg 1 is the trial worktree root (default: current directory).
set -u

root="${1:-.}"
target="$root/benchmarks/sandbox/deploy.sh"

[ -f "$target" ] || { echo "FAIL: $target is missing"; exit 1; }

if ! head -n 1 "$target" | grep -Eq '^#!(/usr/bin/env |/bin/)(ba)?sh$'; then
  echo "FAIL: first line is not a sh/bash shebang"
  exit 1
fi

if ! head -n 5 "$target" | grep -qx 'set -euo pipefail'; then
  echo "FAIL: line 'set -euo pipefail' not present in the first 5 lines"
  exit 1
fi

strict_count=$(grep -c '^set -euo pipefail$' "$target" 2>/dev/null || true)
if [ "$strict_count" -ne 1 ]; then
  echo "FAIL: expected exactly one strict-mode line, found $strict_count"
  exit 1
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
baseline="$here/../sandbox/deploy.sh"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
sed '/^set -euo pipefail$/d' "$target" > "$tmp"
if ! cmp -s "$baseline" "$tmp"; then
  echo "FAIL: script content changed beyond the strict-mode insertion"
  exit 1
fi

echo "PASS: sh-strict-mode"
exit 0
