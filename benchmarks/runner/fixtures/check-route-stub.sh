#!/usr/bin/env sh
# check-route-stub.sh -- test-only stub for benchmarks/runner/route.py.
# Emits ONE JSON line with check-route.py's emit() keys, status "not-applicable"
# (a flexible tier resolves here), exit 0 -> route.py must report captured=True.
# Real operators never pass --check-route-cmd. POSIX sh, ASCII only, no personal paths.
printf '%s\n' '{"status":"not-applicable","reason":"tier-resolves-to-flexible","expected_model":"flexible","expected_effort":"none","observed_model":"","observed_effort":""}'
exit 0
