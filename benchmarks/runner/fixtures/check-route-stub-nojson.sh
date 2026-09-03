#!/usr/bin/env sh
# check-route-stub-nojson.sh -- test-only stub for benchmarks/runner/route.py.
# Prints non-JSON on stdout and exits 0. route.py must map ANY missing / unparseable
# stdout line to captured=False regardless of exit code (fail-closed).
# POSIX sh, ASCII only, no personal paths.
printf '%s\n' 'hello'
exit 0
