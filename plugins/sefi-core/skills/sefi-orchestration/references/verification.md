# Verification -- the canonical verification behavior

This is the one place the verification signal's actual behavior is defined, the same way
`goal-intake.md` defines `goal_intake` and `close-out.md` defines `close_out`. Every agent
or skill that declares `verification` in its agentic-signals line links here in one line
and never restates it.

## The rule
Every claim of "done," "fixed," or "safe" is checked by execution or independent review
before it is trusted. The check is judged by a party other than the one that produced the
work, against a concrete artifact -- never accepted as the producer's self-report.

## When it fires
At every "done" claim, not only at a final handoff: a generator's slice, a retro loop's
proposed edit, and a security finding's "clean" verdict are each a claim of done/fixed/safe
and each needs an independent check before anything downstream trusts it.

## Why (grounded in the declaring skills)
- `loop-engineering`'s Verification move names the shape directly: the qa-engineer plus an
  executed stop condition, judged separately from the generator that produced the work.
  Its "Stop condition = a grep-countable artifact, not a self-declaration" section is the
  same rule stated as a warning -- AutoGPT's `finish`-tool self-completion and a
  predecessor's 184-green-tests-half-unwired build are both what happens when a producer
  is allowed to certify its own output.
- `retro-improve`'s "Verify before applying (not after)" rule hands the proposed edit to
  the qa-engineer, together with the specific failure evidence it targets, BEFORE the edit
  is committed -- never after. The retro loop explicitly cannot self-certify its own edit
  as effective, the same way the software-engineer cannot self-certify a slice.
- `security-review`'s "Review the diff, not the intentions" framing is verification applied
  to code: the reviewer checks what shipped, not what the author meant to ship, and every
  finding or clean verdict cites file:line or the surfaces actually reviewed -- never a
  self-report with nothing checkable behind it.

## Binary self-test
Every "done," "fixed," or "safe" claim in this cycle was checked by execution or by a
party other than the producer, against a concrete artifact. A claim resting only on the
producer's own say-so is a violation.
