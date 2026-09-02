#!/usr/bin/env sh
# check-route-stub-unavailable.sh -- test-only stub for benchmarks/runner/route.py.
# check-route.sh returns status "unavailable" exit 1 unconditionally for claude-code
# (it exposes no per-agent route readback). route.py must STILL report captured=True:
# the trial stays scoreable and the separate route-correctness axis reads model=unchecked.
# POSIX sh, ASCII only, no personal paths.
printf '%s\n' '{"status":"unavailable","reason":"harness-exposes-no-route-readback","expected_model":"placeholder-model","expected_effort":"high","observed_model":"","observed_effort":""}'
exit 1
