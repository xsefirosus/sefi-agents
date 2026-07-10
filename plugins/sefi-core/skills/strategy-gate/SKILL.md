---
name: strategy-gate
description: Use when judging a trading-strategy artifact against hard performance gates and assigning a tier. Opens with the Rule block for profit factor, drawdown, expectancy, and coefficient-of-variation thresholds at 4-6 folds plus the tier ladder; gate math and worked examples live in references/gate-math.md.
managed-by: sefi-agents
---

# Strategy Gate

Signature skill. This body is the Rule block; the gate math and worked examples live in
`references/gate-math.md`, read on demand.

User instructions always override this skill.

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## Rule block (all gates must hold; no "close enough")
Judged across 4-6 walk-forward folds:
- Profit factor >= 1.30
- Max drawdown <= 5%
- Expectancy >= 0.20R
- Coefficient of variation <= 0.25

A single failed gate blocks promotion. Never loosen a gate.

## Tier ladder
paper_ready_candidate -> paper_ready -> live_candidate -> live_ready.
- Promote one rung only when every gate holds on fresh folds.
- Demote by restoring the last known-good tier, not by rebuilding from scratch.
- Promotion to live_ready is a recommendation for a human, never an automated action.

## 5-phase shape
1. Scoping: confirm 4-6 folds exist; else REJECT as insufficient evidence.
2. Compute the metrics across folds.
3. Interpret against thresholds.
4. Tiered verdict.
5. Re-test cadence: name when it must be re-judged.

Sanity-check outputs: an implausibly high profit factor is flagged suspect, not trusted.
See `references/gate-math.md` for formulas and worked examples.

Self-test: every gate has a computed value and a PASS/FAIL, and no gate was loosened.
