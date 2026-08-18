# Human Checkpoint -- the canonical never-auto-merge rule

This is the one place the rule is stated. Every agent, skill, and loop that can reach a
merge, deploy, or destructive action links here in one line and never restates it.

## The rule
Loops open PRs; they never merge. A loop, agent, or automation never auto-merges, never
force-pushes, never deploys to production, and never takes an irreversible or destructive
action (drop-table, delete-worktree of unmerged work, mass-delete) on its own authority.
Anything below the qa-engineer's confidence bar lands in `inbox/` for a human. Every merge,
deploy, or destructive step traces to an explicit human approval recorded in `inbox/`.

## Why (first-party precedent)
A predecessor system removed its own 5-cycle autonomous execute-review-retry loop in favor of a human
decision on every non-approval (IMPLEMENTATION_PLAN_V2, Ground Rule 4: "every round is a
deliberate human choice, not an autonomous retry budget"). An autonomous retry budget
hides a bad call inside more automation; a human checkpoint shortens the distance from
mistake to discovery, which is the whole point of the gate.

## Response contract (validated by a second framework)
The reply shape a human gives at any checkpoint is `docs/LOOPS.md`'s three-way inbox
contract: confirm / change `<free-text>` / exit. MetaGPT's `AskReview` independently
arrived at the same three-way shape for its own human-in-loop gate -- external
corroboration that this is the minimal, sufficient contract for an approval gate,
not a convention invented here without precedent.

## Enforcement, stated honestly
Until now this rule was prose only -- confirmed live (2026-08-18) when an
engineering-manager session used Bash to write files its own `disallowedTools` list
forbids, the same class of gap that would let a Bash-capable agent push straight to
`main` with nothing to stop it. `/sefi:init` now installs `templates/hooks/pre-push` as
`.git/hooks/pre-push`, refusing a direct push to `main`/`master` unless
`SEFI_ALLOW_MAIN_PUSH=1` is set deliberately.

This is defense-in-depth, not the fix. A Bash-capable agent can still route around a
local hook -- edit it, delete it, or run `git push --no-verify`, which skips hooks by
design. The only backstop that survives that is a branch protection rule on the remote
(GitHub Settings -> Branches -> require a PR, block force pushes), which this hook
cannot configure and does not claim to. Claiming otherwise would be exactly the
overclaim the anti-hallucination skill forbids.

## Binary self-test
Every merge / deploy / destructive step in a loop turn traces to an explicit human
approval. If any does not, the loop is violating this rule.
