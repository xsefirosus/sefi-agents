# ANTIPATTERNS

The failure modes this repo is built to avoid, each with a symptom and the fix that lives in
the tree.

## The five failures

### 1. Nodding (self-grading)
- Symptom: the agent that wrote the code also judges it, and praises itself "done" while the
  work is broken.
- Fix: generator/evaluator separation. A separate adversarial judge (the qa-engineer),
  with different instructions and a different model where the runtime allows, decides
  PASS/REJECT against executed evidence. A same-agent "guardrail retry" is not a
  substitute.

### 2. Amnesiac (no memory)
- Symptom: each run re-derives context from scratch and loses prior decisions.
- Fix: the file-based memory vault (`memory-protocol`) plus committed `state/*.md` with a
  6-field resume block, so a cold restart recovers where it left off.

### 3. Manual (no loop)
- Symptom: work that should discover-and-repeat is driven by hand every time.
- Fix: loop engineering -- schedulable loops that implement all five moves (discovery,
  handoff, verification, persistence, scheduling).

### 4. Blind (unverified claims)
- Symptom: unwired code ships because no one executed it; a report's "tests pass" is trusted.
- Fix: the qa-engineer executes to verify (the wired / delete-the-line test) and
  `validate-no-orphans.sh` flags fully-written-but-unwired artifacts.

### 5. Tangled (drift and duplication)
- Symptom: a load-bearing rule exists as N slightly-different per-file copies; agents depend
  on each other's internals; a cheap model drifts from the spec.
- Fix: one canonical statement per rule (e.g. never-auto-merge in `human-checkpoint.md`),
  independent agents, and the `scripts/ci/` conformance suite.

## The over-build trap
- Symptom: writing more code than the task needs -- a new helper where reuse would do, a
  framework where one line would do.
- Fix: the software-engineer climbs the code-minimization ladder before writing and stops
  at the first rung that holds. Token discipline starts with building less, not phrasing
  tighter.

## External evidence for the generator/evaluator mandate
- AutoGPT's reflection step has the *same* LLM generate, critique, and refine its own output
  (its docstring says so) -- the self-grading pattern, shipped as a default.
- mem0's April-2026 change demoted silent auto-overwrite of memories from default to opt-in
  -- independent evidence that memory maintenance must be append-only or flag-for-review.

## First-party evidence (Earl's own predecessor build; one row per live failure)

| Predecessor failure (live) | Fixed here by |
|---|---|
| 184 green tests, half the modules unwired (integration gap) | qa-engineer protocol item 3 (wired / delete-the-line) + `validate-no-orphans.sh` |
| a test re-implementing the feature in its own body | qa-engineer protocol item 3 |
| self-graded "done" false three audits running | generator/evaluator separation; never self-certify |
| improvement loop inert for days (metrics vs edit-target keyspace mismatch) | retro-improve single-keyspace + edit-what-runtime-loads; `state/metrics.md` keyed by file path |
| 8 invented states, diverged schemas (spec drift on a cheap model) | `scripts/ci/` conformance suite |
| placebo infra (sleep-loop container, zero-caller writers, false-alarm probe) | `validate-no-orphans.sh`, honest-telemetry convention |
| n8n as a control-loop hop (4 hops, false health alarms) | direct API calls in own loops; n8n stays a client-deliverable skill |
| whole build ran before first git commit | loops run only inside git worktrees with PR checkpoints |
