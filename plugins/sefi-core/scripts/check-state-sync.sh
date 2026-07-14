#!/usr/bin/env bash
# check-state-sync.sh -- flags drift between a project's loops/*.loop.md and the
# state/<name>.md file it names. Advisory: reports, never exits nonzero (matches this
# repo's report-don't-act convention for broad scans). Run after editing a loop spec and
# before scheduling it.
set -uo pipefail

DIR="loops"

[ -d "$DIR" ] || { echo "check-state-sync: no $DIR/ directory (run /sefi:init first)" >&2; exit 0; }

for f in "$DIR"/*.loop.md; do
  [ -e "$f" ] || continue
  loop="$(basename "$f" .loop.md)"

  state_ref="$(grep -oE 'state file: `[^`]+`' "$f" | head -1 | sed -E 's/state file: `([^`]+)`/\1/')"

  if [ -z "$state_ref" ]; then
    echo "DRIFT: $loop - no 'state file:' line found under Persistence"
    continue
  fi
  if [ ! -f "$state_ref" ]; then
    echo "DRIFT: $loop - names $state_ref, which does not exist yet (expected before first run)"
    continue
  fi
  if ! grep -q '## Resume and Execution Handoff' "$state_ref"; then
    echo "DRIFT: $loop - $state_ref exists but is missing the '## Resume and Execution Handoff' block"
    continue
  fi
  echo "OK: $loop <-> $state_ref in sync"
done
