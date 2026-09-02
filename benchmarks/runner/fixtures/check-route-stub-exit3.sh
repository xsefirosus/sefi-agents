#!/usr/bin/env sh
# check-route-stub-exit3.sh -- test-only stub for benchmarks/runner/route.py.
# Mimics check-route.sh's "no usable interpreter" path: a notice on stderr, NO JSON on
# stdout, exit 3. route.py must map this to captured=False (fail-closed).
# POSIX sh, ASCII only, no personal paths.
printf '%s\n' 'check-route: no python3 or python 3.11+ interpreter available; route check skipped' >&2
exit 3
