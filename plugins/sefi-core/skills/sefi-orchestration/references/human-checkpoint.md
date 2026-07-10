# Human Checkpoint -- the canonical never-auto-merge rule

This is the one place the rule is stated. Every agent, skill, and loop that can reach a
merge, deploy, or destructive action links here in one line and never restates it.

## The rule
Loops open PRs; they never merge. A loop, agent, or automation never auto-merges, never
force-pushes, never deploys to production, and never takes an irreversible or destructive
action (drop-table, delete-worktree of unmerged work, mass-delete) on its own authority.
Anything below the evaluator's confidence bar lands in `inbox/` for a human. Every merge,
deploy, or destructive step traces to an explicit human approval recorded in `inbox/`.

## Why (first-party precedent)
Sefi-OS removed its own 5-cycle autonomous execute-review-retry loop in favor of a human
decision on every non-approval (IMPLEMENTATION_PLAN_V2, Ground Rule 4: "every round is a
deliberate human choice, not an autonomous retry budget"). An autonomous retry budget
hides a bad call inside more automation; a human checkpoint shortens the distance from
mistake to discovery, which is the whole point of the gate.

## Binary self-test
Every merge / deploy / destructive step in a loop turn traces to an explicit human
approval. If any does not, the loop is violating this rule.
