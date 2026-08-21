# Decision note candidate — strategy-gate verdict: dual-ema-crossover (synthetic demo)

- **tags:** [decision, strategy-demo]
- **aliases:** ["dual-ema-crossover gate verdict 2026-08-20"]
- **status:** proposed
- **decided:** 2026-08-20
- **tier:** trace
- **scope:** session
- **keywords:** strategy-gate, dual-ema-crossover, max-drawdown, walk-forward, paper_ready_candidate
- **managed-by:** sefi-agents

Digest for the knowledge-manager (vault write is the knowledge-manager's job; this is a
candidate only).

## Verdict

Tier: **paper_ready_candidate** — blocked from paper_ready by the max_drawdown gate.

## Gate table (all values independently recomputed from the fold CSVs; match metrics.json within 1e-9)

| Metric | Threshold | fold-01 | fold-02 | fold-03 | fold-04 | fold-05 | Aggregate | Verdict |
|---|---|---|---|---|---|---|---|---|
| Profit factor | >= 1.30 | 1.8510 | 1.8820 | 1.8426 | 2.4118 | 2.2669 | — | PASS |
| Max drawdown | <= 5% | 5.96% FAIL | 7.59% FAIL | 6.12% FAIL | 5.72% FAIL | 4.68% | — | **FAIL (4/5 folds)** |
| Expectancy | >= 0.20R | 0.3737 | 0.3977 | 0.3794 | 0.5609 | 0.5165 | — | PASS |
| CoV | <= 0.25 | — | — | — | — | — | 0.1616 | PASS |

## Blocking fold

max_drawdown gate — fold-02 worst at 7.59%; folds 01–04 all exceed 5.0%. Next run (if any
strategy change is proposed) should start by addressing the drawdown profile, not
rebuilding from scratch.

## Evidence

- D:\Projects\strategy-demo\gate-verdict.md (full verdict)
- D:\Projects\strategy-demo\validation.log: ALL CHECKS PASSED
- Executed: generator.py rerun (self-check PASS); independent gate_verify.py (ALL INTERNAL CHECKS PASS)
- Escalation: inbox\2026-08-20-strategy-gate-maxdd-fail.md (max_drawdown gate FAIL)