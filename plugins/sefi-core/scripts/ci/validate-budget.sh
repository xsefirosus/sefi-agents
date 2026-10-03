#!/usr/bin/env bash
# validate-budget.sh -- budget.yml declares a per-run cap, daily cap,
# per-dispatch cap, max-retries, max-parallel-worktrees, and per-agent return-token
# cap; fail if any is missing or unbounded (non-numeric). billing_mode is optional:
# when absent, budget-check.sh resolves a per-harness default (opencode and hermes
# free, codex and claude-code flat, unknown harness metered); when present it must
# carry one of metered, flat, free -- declared with no value it is an error, not a
# request for the default -- and the explicit value always wins.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CONFIG="$ROOT/plugins/sefi-core/templates/config/budget.yml"
rel="plugins/sefi-core/templates/config/budget.yml"

[ -f "$CONFIG" ] || { echo "ERROR: $rel - not found"; exit 1; }

errors=0
required="per_run_usd_cap daily_usd_cap per_dispatch_usd_cap max_retries max_parallel_worktrees per_agent_return_tokens per_agent_return_tokens_target"

for key in $required; do
  val="$(sed -n "s/^$key:[[:space:]]*\([0-9][0-9.]*\).*/\1/p" "$CONFIG" | head -1)"
  if [ -z "$val" ]; then
    echo "ERROR: $rel - missing or unbounded cap '$key'"; errors=$((errors + 1))
  fi
done

mode="$(sed -n "s/^billing_mode:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
declared="$(grep -c '^billing_mode:' "$CONFIG" || true)"
# Absent is allowed (budget-check.sh resolves the per-harness default); present-but-empty
# is a config error. The two are indistinguishable from $mode alone -- a keyless config and
# a key with nothing after the colon both yield an empty string -- so the declaration count
# is what separates them. Reading empty as "use the default" would pass a config that
# budget-check.sh refuses to run.
if [ "$declared" -gt 0 ] && [ -z "$mode" ]; then
  echo "ERROR: $rel - billing_mode is declared with no value (expected metered, flat, or free; remove the key to use the per-harness default)"
  errors=$((errors + 1))
fi
case "$mode" in
  ""|metered|flat|free) : ;;
  *) echo "ERROR: $rel - billing_mode must be one of metered, flat, free (got '${mode:-<missing>}')"; errors=$((errors + 1)) ;;
esac

if [ "$errors" -ne 0 ]; then echo "validate-budget: $errors error(s)"; exit 1; fi
echo "validate-budget: OK (all caps present and bounded)"
