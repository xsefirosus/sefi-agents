# Gate Math and Worked Examples

Formulas and examples behind the strategy-gate Rule block.

## Formulas
- Profit factor = gross profit / gross loss. >= 1.30 required.
- Max drawdown = largest peak-to-trough equity decline, as a percent of peak. <= 5%.
- Expectancy (in R) = (win rate * avg win in R) - (loss rate * avg loss in R). >= 0.20R.
- Coefficient of variation (CoV) = stddev(fold returns) / mean(fold returns). <= 0.25. CoV
  measures consistency across folds; a low mean with high variance fails here even if the
  aggregate looks fine.

## Walk-forward folds
Split the sample into 4-6 sequential train/test folds. Compute each metric per fold and
judge the distribution, not a single blended number -- a strategy that passes on average
but fails 2 of 5 folds is not paper_ready.

## Worked example (PASS)
Folds PF: 1.42, 1.38, 1.55, 1.31, 1.40. All >= 1.30. Max DD across folds: 4.1%. Expectancy:
0.27R. CoV of fold returns: 0.18. All gates hold, so promote one rung.

## Worked example (REJECT)
Folds PF: 1.9, 1.1, 2.2, 0.95, 1.6. Two folds < 1.30, so REJECT despite a high average. The
spread also pushes CoV to 0.34 (> 0.25). Flag the high-PF folds as suspect, not as proof.

## Demotion
On a failed re-test, restore the last known-good tier and cite the fold that broke, so the
next run starts there rather than rebuilding.
