---
tags: [inbox, strategy-gate, needs-human]
date: 2026-08-20
from: quant-analyst
status: open
managed-by: sefi-agents
---

# Strategy-gate FAIL — max drawdown (dual-ema-crossover, synthetic demo)

**Item:** the max_drawdown gate FAILED for 4 of 5 walk-forward folds in
D:\Projects\strategy-demo (strategy: dual EMA 10/30 crossover, ATR risk).

## Evidence (independently recomputed from fold CSVs; matches metrics.json within 1e-9)

| Fold | Max drawdown | Threshold (<= 5%) |
|---|---|---|
| fold-01 | 5.9615% | FAIL |
| fold-02 | 7.5890% | FAIL |
| fold-03 | 6.1173% | FAIL |
| fold-04 | 5.7200% | FAIL |
| fold-05 | 4.6793% | PASS |

All other gates PASS: profit factor 1.84–2.41 (>= 1.30), expectancy 0.37–0.56R
(>= 0.20R), CoV 0.1616 (<= 0.25).

## Verdict

Tier **paper_ready_candidate** — blocked from paper_ready by the max_drawdown gate.
Full verdict: D:\Projects\strategy-demo\gate-verdict.md

## Escalation SLA

Flagged to inbox/ within 2 minutes (or before this turn ends, whichever is sooner) —
this item is that flag.

## Human reply contract (confirm / change / exit)

- **confirm** — accept the verdict; strategy stays paper_ready_candidate, no promotion.
- **change: <free-text>** — e.g., direct the engineering-manager to re-test with a
  tightened risk profile (smaller risk-per-trade or stop distance), then re-dispatch the
  quant-analyst on fresh folds.
- **exit** — close this item; no further action.