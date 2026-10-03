#!/usr/bin/env bash
# validate-budget.sh -- budget.yml declares billing_mode, a per-run cap, daily cap,
# per-dispatch cap, max-retries, max-parallel-worktrees, and per-agent return-token
# cap; fail if any is missing or unbounded (non-numeric), or if billing_mode is not
# one of metered, flat, free.
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
case "$mode" in
  metered|flat|free) : ;;
  *) echo "ERROR: $rel - billing_mode must be one of metered, flat, free (got '${mode:-<missing>}')"; errors=$((errors + 1)) ;;
esac

if [ "$errors" -ne 0 ]; then echo "validate-budget: $errors error(s)"; exit 1; fi
echo "validate-budget: OK (all caps present and bounded)"
