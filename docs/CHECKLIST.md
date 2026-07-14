# CHECKLIST

Run this before shipping a loop and when auditing a finished one.

## Six elements every loop must name before shipping
1. Trigger / Scheduling -- cloud cron or local interval.
2. Discovery -- the skill that finds the work and the inputs it reads.
3. Handoff -- one worktree per finding, with the branch naming and max parallel.
4. Verification -- generator plus a separate judge (the qa-engineer), judged against an
   executed stop condition.
5. Persistence -- the committed `state/*.md` with a 6-field resume block and the metrics row.
6. Human checkpoint -- the one thing that is never automated.

A loop missing any element does not ship. `validate-loops.sh` enforces the five moves and
the human-checkpoint line.

## The four silent costs (they accrue whether or not you notice)
- Verification debt: unverified claims pile up until one fails loudly in production.
- Comprehension rot: code no one has read end to end becomes unmaintainable.
- Cognitive surrender: trusting the agent's "done" instead of checking it.
- Token blowout: an unbounded loop or dispatch burning budget with nothing to show.

## Standing disciplines
- Daily sampled review of loop output while a loop is young.
- Caps in `config/budget.yml` set before the first unattended run, never after.
- One permanent human checkpoint that never gets optimized away.

## Sampled-review / audit skeleton
Method migrated from the predecessor's audit that caught what three rounds of self-reported "done"
missed.
- Verify claims against artifacts: no prior status claim -- including check-mark markers in
  docs and plans, and "tests pass" lines -- is trusted without opening the file or re-running
  the command.
- Cite every finding to a file and line.
- Back any runtime-behavior claim with a live log line or a probe, not a reading of the code.
- Report in this fixed section order, severity-ranked, each item naming its file and its fix:
  1. Working
  2. Bugs
  3. Missing
  4. Nice-to-have
  5. Should-be-removed
  6. Prioritized punch list
