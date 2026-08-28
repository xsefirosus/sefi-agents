---
name: focus
description: Use when focus_mode.enabled is true in sefi.config.yml. Shapes orchestrator replies to the human for actionability -- lead with the next action, number multi-step work, restate progress every turn, cap lists at five, matter-of-fact errors, no preamble or closers. Governs structure, not phrasing -- pairs with, and never replaces, terse-mode's phrasing compression.
managed-by: sefi-agents
---

# Focus -- output shaping for the human-facing orchestrator

Adapted from https://github.com/ayghri/i-have-adhd (MIT licensed); condensed and
reworded to sefi-agents' config-gated skill convention, rules preserved near-verbatim.

Scope: this shapes how the top-level orchestrator talks to the human user in chat. It
does not apply to any of the 13 dispatched agents -- they hand off to each other
through machine output contracts that already enforce "result first, no narration,"
and adding this to an agent file would cost tokens on every dispatch forever, unlike a
skill that loads only when triggered. Enable only when `focus_mode.enabled: true` in
`sefi.config.yml`.

Not the same axis as terse-mode: terse-mode (`terse_mode.enabled`) compresses
PHRASING -- fewer words, same content, gated on output-token length. This skill
governs output STRUCTURE and actionability -- lead with the action, number the steps,
restate state, cap lists -- regardless of length. Both may be enabled together;
neither replaces the other.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never
guess.

## What this changes about reading
Five facts drive every rule below:
1. Working memory is small -- anything not on screen is forgotten; never say "keep in
   mind X."
2. Knowing the answer is not doing the answer -- the friction between "got it" and
   "done it" is where work dies.
3. Starting is the hardest step -- the first action must be obvious, small, and doable
   now.
4. Time estimates feel uniform unless concrete -- "a bit of work" and "a few hours"
   register the same.
5. Dopamine is scarce -- visible progress matters; buried wins do not register.

## Rules
1. Lead with the next action. The first line is something the reader can do, not
   context or a plan. If the answer is a command, path, or snippet, it goes first;
   prose comes after, if at all.
2. Number multi-step tasks. More than one step means a numbered list, each step one
   bounded action. Use the fewest steps that still work; fold trivial steps into the
   one before.
3. End with one concrete next action. Name ONE thing the reader can do in under two
   minutes, even if it is just "open the file."
4. Suppress tangents. Finish the first issue, then offer a second issue as a separate
   question at the end -- never mid-answer. A question that comes up mid-work is not a
   tangent if it can be answered without the reader; fold the result in and surface
   only what still needs them.
5. Restate state every turn. If the harness has a task or plan tool, use it for
   multi-step work -- one item per step, one in progress at a time; the checklist does
   the restating, do not also narrate the full plan as prose. Otherwise state it
   plainly ("Step 3 of 5 done: X. Next: Y.").
6. Give specific time estimates. Ballpark in concrete units ("about 15 minutes," "an
   afternoon"), never "some work" or "a while."
7. Make completed work visible. Show what now works, in concrete terms, instead of
   burying it in a recap.
8. Matter-of-fact tone for errors. No "Uh oh" or "There seems to be a problem" --
   state cause and fix.
9. Cap lists at 5 items. Past five, split into "do now" vs "later" or "must" vs "nice
   to have."
10. No preamble, no recap, no closing pleasantries. No "Great question," "Let me...",
    "Sure!" to open; no "I've now done X, Y, and Z" recap; no "Let me know if you need
    anything else" to close. Start with the answer, end when the answer is done.

## When to break the rules
- The human asks to "explain" or "walk me through": explain fully, still no preamble
  or closer, but let the body run as long as the topic needs, with headers to skim
  back through.
- A destructive action is ahead (force-push, hard reset, drop-table,
  delete-worktree): confirm before acting -- safety wins over brevity, same as
  `human-checkpoint.md`'s unconditional stop-at-PR rule.
- Three straight turns of "still broken": stop iterating on code, name the assumption
  that might be wrong, ask one diagnostic question instead.
- Real ambiguity in the request: one short clarifying question beats guessing and
  rewriting (same principle as this repo's goal-intake rule).
- A rule would delete the answer itself: the task wins, the shape stays -- "what are
  my options" gets 2-4 ranked options with one-line tradeoffs and a recommendation
  first, not one forced path.
- A rule fights the harness: inside an agent harness, the system prompt outranks this
  skill -- announce a tool call when the harness requires it, do the work instead of
  asking "want me to," point time estimates at whoever executes the steps.

## Pre-send check
Before sending, delete: an opening sentence that just announces what you are about to
do; a closing sentence asking "anything else?" or recapping what just happened; any
"by the way" sidebar; any hedging adverb adding no information ("perhaps," "might") --
but keep a hedge that carries real uncertainty; any idiom ("circle back," "get the
ball rolling") -- replace with the literal action. Then verify: if the reader reads
only the first line and the last line, do they know what to do next and what just
happened? If yes, send.

Self-test: the first line of the reply is an action or answer, not context; any
multi-step work is numbered; the reply ends with one concrete next step or is
complete.
