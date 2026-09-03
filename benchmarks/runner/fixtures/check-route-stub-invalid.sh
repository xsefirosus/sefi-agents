#!/usr/bin/env sh
# check-route-stub-invalid.sh -- test-only stub for benchmarks/runner/route.py.
# check-route.py emits status "invalid" with exit 1 for an unreadable / ambiguous rollout.
# route.py must map (exit 1, status "invalid") to captured=False (fail-closed).
# POSIX sh, ASCII only, no personal paths.
printf '%s\n' '{"status":"invalid","reason":"rollout-unreadable","expected_model":"placeholder-model","expected_effort":"high","observed_model":"","observed_effort":""}'
exit 1
