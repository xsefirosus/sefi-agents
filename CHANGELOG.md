# Changelog

All notable changes to sefi-agents are documented here. Format follows Keep a
Changelog; this project adheres to Semantic Versioning.

## [0.3.15] - 2026-08-19

### Fixed

1. **Neither `install.sh` nor `install-opencode.sh` ever wired `hooks/hooks.json` into an
   installed destination -- meaning `check-bash-write.sh`'s `disallowedTools`-survives-
   `Bash` guarantee (README's own v0.3.6 row) was silently inert for every fallback
   install.** Found live, in this exact session: a dispatched `support-engineer` (which
   declares `disallowedTools: Write, Edit, MultiEdit`) ran `git commit` via Bash
   completely uncaught, because the `PreToolUse` hook meant to block exactly that was
   never registered anywhere Claude Code would read it from -- confirmed by checking this
   container's real `~/.claude/settings.json`, which had zero mention of
   `check-bash-write.sh`.

   Fix, scoped honestly to what it can actually guarantee: `install.sh --target claude`
   now merges `hooks/hooks.json` into `$DEST/settings.json`'s own `hooks` key (both
   `SessionStart` and `PreToolUse:Bash`), with `${CLAUDE_PLUGIN_ROOT}` resolved to a
   literal path -- via `jq`, since a hand-rolled JSON merge risks corrupting a real user's
   existing settings (their own unrelated hooks, permissions). Idempotent (safe to
   re-run), preserves any pre-existing unrelated hooks/permissions untouched (proven, not
   assumed), and warns plainly rather than silently skipping if `jq` isn't on PATH.

   Two things this does NOT claim to fix, stated plainly rather than left implied:
   Hermes is not wired here at all -- this repo does not know Hermes's own hook config
   format, and inventing one would be an unbacked claim, the same honesty already applied
   to Hermes/Codex in the existing check-bash-write.sh README row. OpenCode needs no
   equivalent change -- `install-opencode.sh`'s existing `emit_bash_write_gate()` already
   generates an equivalent bash-deny-pattern permission block per agent, because OpenCode
   has no separate hooks mechanism to hang this off of the way Claude Code does.

   5 new regression assertions (125 -> 130), including a real merge-safety proof (a
   pre-seeded unrelated `Stop` hook and `permissions` block survive two consecutive
   installs untouched, with no duplication) and a real jq-missing-PATH proof, both
   verified via re-break/restore against the actual fix.

## [0.3.14] - 2026-08-19

### Fixed

1. **`install.sh --copy`'s `${CLAUDE_PLUGIN_ROOT}` resolution pass was gated on every
   subdirectory copying cleanly, so one pre-existing conflict skipped it for everything.**
   Found live, in this exact repo, installing v0.3.13's own fix into a real `~/.claude`:
   a pre-existing `skills/` from an earlier install (correctly refused without `--force`,
   the safe behavior) set `rc=1`, and the substitution pass was conditioned on `rc -eq 0`
   -- so `agents/` and `commands/`, which copied successfully and had nothing to do with
   the `skills/` conflict, were left with the literal `${CLAUDE_PLUGIN_ROOT}` placeholder
   unresolved. The exact bug 0.3.13 shipped to fix, reintroduced by 0.3.13's own gating
   logic on any partial install.

   Fix: the substitution pass no longer depends on `rc`; it runs unconditionally in copy
   mode against whichever subdirectories actually exist at the destination (freshly
   copied this run, or already present from a prior one), guarded only by
   `[ -d "$DEST/$sub" ]`. It's idempotent -- a no-op sed on content with no placeholder
   left -- so running it regardless of `rc` is always safe. New regression case in
   `test-scripts.sh` reproduces the exact conflict shape (a pre-seeded `skills/` dir) and
   proves `agents`/`commands` still resolve anyway; proven via re-break/restore against
   the actual fix, not just written to pass. 2 new assertions (123 -> 125).

## [0.3.13] - 2026-08-18

### Fixed

1. **24 agent/skill instructions told a dispatched agent to "run scripts/x.sh" as a bare
   relative path with no stated resolution rule, and neither `install.sh` nor
   `install-opencode.sh` ever copied `plugins/sefi-core/scripts/` into an installed
   destination at all.** Found live by another session running this repo's own `main` via
   `install-opencode.sh`, then independently re-verified here rather than taken on trust:
   read both installers end to end (confirmed neither touches `scripts/`), and confirmed
   via an official-docs lookup that `${CLAUDE_PLUGIN_ROOT}` is inline-substituted by Claude
   Code's native plugin loader anywhere it appears in loaded agent/skill markdown -- the
   same mechanism `hooks/hooks.json` already relies on for its two hook scripts -- but that
   substitution is specific to the native `/plugin install` path, not to `install.sh`'s own
   "human fallback for non-plugin runtimes" (its own header's words).

   Two-part fix, matching the two-part gap: (1) all 24 references across 16 agent/skill
   files now read `${CLAUDE_PLUGIN_ROOT}/scripts/x.sh`, fixing this repo's documented
   primary install path (`/plugin marketplace add` + `/plugin install`) outright -- Claude
   Code's own loader resolves the placeholder, no repo-side machinery needed. (2)
   `install.sh` and `install-opencode.sh` now also copy `scripts/` into every destination,
   and in copy mode (always-on for OpenCode; `--copy` for `install.sh`) additionally
   rewrite the `${CLAUDE_PLUGIN_ROOT}` placeholder to a literal resolved path across every
   copied agent/skill/command file, so a copied install needs no runtime understanding of
   the placeholder at all -- verified against real temp directories (`HERMES_HOME=`, then
   `OPENCODE_HOME=`), not asserted.

   Stated honestly, not silently left implied-fixed: `install.sh`'s DEFAULT symlink mode
   gets the files (`scripts/` becomes reachable) but not the placeholder resolution, since
   rewriting a symlinked file's content would mutate the source checkout -- a known,
   documented gap in the script's own header, not a claim of completeness this fix does
   not earn.

   New validator `scripts/ci/validate-script-refs.sh` -- the direction `validate-links.sh`
   cannot see: that script proves a `scripts/x.sh` reference resolves on disk, in this
   checkout; it says nothing about whether a dispatched agent can find it at runtime from
   an installed destination. Wired into `run-all.sh` after `validate-links.sh`. 6 new
   regression assertions in `test-scripts.sh` (117 -> 123), including a re-break/restore
   proof against the live `qa-engineer.md` and real installer runs against real temp
   directories for both `install.sh --copy --target hermes` and `install-opencode.sh`.

## [0.3.12] - 2026-08-18

### Fixed

1. **The Bash-write gate and the CI worked-example extraction trusted `command -v
   python3` presence without checking the interpreter runs.** On the triage machine
   `python3` was the Microsoft Store alias stub -- present on PATH, prints "Python was not
   found", exits nonzero -- so `extract_command()`/`extract_agent_type()` returned empty
   and sed -i/tee failed OPEN (exit 0 instead of 2) while a working Python 3.11.15 sat on
   PATH as `python`. The same root cause reddened local CI on that host (3 failed / 89
   passed: test-scripts.sh line 603's swallowed extraction -> "could not extract the
   worked example", and the two expected exit-2 cases). The fix is a health-checked
   resolver chain (jq -> python3 -> python -> py, smoke-tested before trust) used by both
   extractors and the extraction; the documented fail-open for hosts with no working
   parser is preserved and pinned by a regression case. CI parity: ubuntu runners have a
   healthy python3 (and jq), so their non-shim behavior is unchanged; the new shim tests
   force the broken-python3 path deterministically there. 3 new regression cases added on
   top of the 114 already on `main` at merge time (counts vary by platform --
   timeout/shellcheck/ccusage skips differ per machine).

## [0.3.11] - 2026-08-18

### Changed

1. **Follow-up questions now fire on a raw, underspecified idea, not only on a
   provably-missing done-condition/scope/value.** `goal-intake.md`'s canonical rule
   broadened by one clause; `prompt-engineer.md`'s Stage-0 escalation (step 5) lowered
   to match, so a bare/raw human idea gets the existing one-question-at-a-time
   `goal_intake` treatment instead of being guessed at or silently restated. No new
   mechanism -- reuses the existing ask-ONE-question/escalate-to-`needs-human` rule
   verbatim; every agent or skill that already declares `goal_intake` in its
   `agentic-signals` line picks this up for free via the shared reference file.

## [0.3.10] - 2026-08-18

### Added

1. **`scripts/check-structure-diff.sh` -- a fast deterministic pre-filter for
   `retro-improve`, wired ahead of its existing qa-engineer judgment call.** Proposal 2
   from the sefi-os contribution brief, NOT a port of its actual shape (stored
   input/expected-output pairs, diffed after running an `executor_func`) -- that does not
   map onto this repo: sefi-agents' agents are LLM-driven markdown prose, not
   deterministic functions, so no `executor_func` reproduces byte-identical output for a
   stored input the way code does. The source doc raised this doubt itself ("may be a
   deliberate design choice... worth asking, not assuming a gap") rather than assuming a
   gap; evaluating it against the current repo confirmed the doubt and found the
   genuinely non-redundant sliver instead: a structural-invariant diff catching a
   silently stripped `tools:` entry, a changed `tier:`, or a missing anti-hallucination
   pointer, the same failure shape `validate-config-wired.sh` catches for config keys,
   applied to agent/skill frontmatter. An addition is never flagged -- this repo's own
   roster gained `tier:` and `agentic-signals:` mid-project, and that is not a
   regression.

   For a routing-relevant target, `retro-improve` also re-runs the ALREADY-SHIPPED
   `validate-routing.sh` / `routing-cases.txt` fixture pair against the proposed edit --
   no parallel baseline-fixture mechanism was built; the one that already existed is
   reused. `retro-improve/SKILL.md` states explicitly why this does not replace
   `state/retro-ledger.md`'s existing revert rule: the ledger's rule is slow and
   statistical by design (3-5 live qa-engineer verdicts accumulated after the edit
   ships); this pre-filter is instant and deterministic, catching a regression before
   the edit is even committed. Neither replaces the other -- same non-duplication
   discipline already applied when `prompt-engineer` was added against `goal_intake`.

   8 new regression assertions (106 -> 114), including a re-break/restore proof against
   the LIVE `routing-table.md` (mutated, confirmed `validate-routing.sh` catches the
   break, restored, confirmed it passes again) -- `validate-routing.sh` resolves its
   fixture path relative to its own script location rather than accepting one as an
   argument, so proving the reused mechanism actually catches a regression meant
   exercising the real file directly, the same discipline already used for
   `scan-placeholders.sh` in 0.3.9.

## [0.3.9] - 2026-08-18

### Added

1. **`scripts/scan-placeholders.sh` -- deterministic post-hoc hallucination-pattern
   scanner.** Sourced from a related project's `orchestrator/hallucination_checker.py`
   after checking it against what already exists here, not assumed: 4 of its 5 pattern
   categories are portable as-is (`uncertain_language`, `incomplete_implementation`,
   `placeholder_content`, `test_urls`); the fifth, `code_generation` (matching
   `def`/`class`/`import`/fenced code blocks), is deliberately excluded, confirmed
   redundant against `check-reply.sh`'s existing foreign-deliverable check (its check 3
   already catches a full HTML/plan-skeleton leak from a read-only agent -- the same
   failure shape `code_generation` was trying to catch more crudely).

   Always exits 0: this is evidence collection for the qa-engineer to judge against a
   slice's Done Criteria, never an automatic verdict -- the same relationship
   `check-bar.sh` has to the bar-comparison evidence type. `qa-engineer.md` gains
   Protocol item 12 pointing at it, in 20 words against a word budget that had ~73 words
   of headroom left across all 14 agents; the new
   `skills/anti-hallucination/references/placeholder-scan.md` carries the per-category
   false-positive guidance a bare hit count cannot (e.g. "probably" inside a sentence
   explaining why something is UNKNOWN is the discipline working, not a violation).

   12 new regression assertions (94 -> 106), including a re-break/restore proof per
   `qa-engineer.md` item 6's own rule: the `TODO:` pattern was temporarily disabled,
   the dependent assertion confirmed to fail, then restored and confirmed to pass again
   -- proving the test exercises the pattern rather than passing by construction.

## [0.3.8] - 2026-08-18

### Added

1. **`per_agent_return_tokens_target: 150` -- a soft target alongside the hard cap.**
   Refines v0.3.7's flat raise (150 -> 200): the user's instruction was "aim for 150,
   200 only if not possible", which needs two numbers, not one. `per_agent_return_tokens`
   (200) stays the hard cap `check-reply.sh` rejects and forces a redo above; the new
   `per_agent_return_tokens_target` (150) is read by the same script and prints a
   non-blocking `NOTE:` when a reply clears the target but stays within the cap -- visible
   feedback that it should aim shorter next time, without spending a wasted redo round-trip
   on a reply that was not actually a contract violation. Added to both `config/budget.yml`
   (this repo's own install) and `templates/config/budget.yml` (what `/sefi:init` hands
   every new project), and to `validate-budget.sh`'s required-key list so a future accidental
   deletion is caught in CI rather than silently degrading the advisory to nothing.

   Deliberately NOT a second hard gate: a target is aspirational by nature (a verdict citing
   evidence may legitimately need more than 150 words), so making it block would just
   reintroduce the miscalibration v0.3.7 fixed, one number lower. `validate-config-wired.sh`
   confirms the new key is genuinely read, not decorative -- the exact failure mode
   `per_agent_return_tokens` itself sat in since v0.2.1 before `check-reply.sh` existed.

   Caught a real bug while writing the regression tests, not shipped it: the first version
   piped `check-reply.sh`'s output live into `grep -q` under this file's own
   `set -o pipefail`. `grep -q` exits the instant it matches without draining its input, so
   the writer can receive SIGPIPE (exit 141) for writing past a closed pipe -- clobbering the
   reported pipeline status even though the match was real, a classic pipefail/`grep -q`
   pitfall. Fixed by capturing output into a variable first and matching with `case`, the
   same idiom this file's own `gate.sh` checks already use. Verified the fix actually catches
   a regression: reverted the advisory logic, confirmed the expected single failure, restored,
   re-ran green. 2 new regression cases (92 -> 94 assertions).

## [0.3.7] - 2026-08-18

### Changed

1. **`per_agent_return_tokens` raised 150 -> 200.** Live data, not a guess: qa-engineer's
   verdict-with-evidence replies (a PASS/REJECT call that has to cite file:line evidence)
   twice landed at 162 and 172 words against the old 150-word cap, both real dispatches, both
   forced through a redo round-trip by `check-reply.sh`. That is not the same output shape as
   engineering-manager's three-line dispatch record, which the same flat number was also
   governing. 200 covers the verdict-with-evidence shape without raising the ceiling far
   enough to stop catching genuine bloat -- the fix that actually caused the redo (an HTML
   document instead of a digest) was hundreds of words over any reasonable cap and still
   fails here. Changed in both `config/budget.yml` (this repo's own install) and
   `templates/config/budget.yml` (what `/sefi:init` hands every new project). A true
   per-agent cap (qa-engineer's evidence-bearing verdicts vs. engineering-manager's terse
   dispatch records) remains open; this is a single recalibrated number, not that redesign.
   Verified the new regression cases actually test the new threshold, not just happen to
   pass: temporarily reverted the cap to 150, confirmed the 172-word case failed exactly as
   expected, restored, re-ran green. 2 new regression cases (90 -> 92 assertions).

## [0.3.6] - 2026-08-18

### Added

1. **Bash-content-write gate -- `scripts/check-bash-write.sh`.** `disallowedTools: Write,
   Edit, MultiEdit` does not survive `Bash`: confirmed live via the engineering-manager's
   own forensic self-audit, which queried its harness's session-log database and found
   itself had used Bash-invoked `Add-Content`/`sed -i` 8 times to write state-file content
   despite that exact line. `disallowedTools` blocks the named tools; it cannot see what a
   still-allowed `Bash` does. This gap applied to 5 agents that fully disallow all three
   write tools -- engineering-manager, qa-engineer, research-analyst, security-engineer,
   support-engineer -- and, more narrowly, to knowledge-manager and quant-analyst (only
   `MultiEdit` denied, real `Write` access retained, so a Bash write is not a bypass of a
   false claim for either).

   The original design put a `PreToolUse` hook directly in each exposed agent's own
   frontmatter. Verified against the docs before wiring it into five files (the same
   look-before-you-leap standard this repo asks of its own agents): "For security reasons,
   plugin subagents don't support the `hooks` ... frontmatter fields. These fields are
   ignored when loading agents from a plugin" (`sub-agents.md`, confirmed independently in
   `plugins-reference.md`) -- a deliberate Claude Code restriction, since a plugin
   intercepting its own subagents' tool calls is itself a capability worth gating. The
   actual fix registers once in `hooks/hooks.json` (which plugins CAN use) and reads the
   standard PreToolUse payload's `agent_type` field to look up that agent's own
   `agents/<agent_type>.md` at runtime, enforcing only when its `disallowedTools` fully
   covers Write, Edit, and MultiEdit. One script stays in sync automatically as agents are
   added or changed; no second list to go stale.

   `install-opencode.sh` gets the OpenCode-native equivalent: an agent that fully disallows
   the three write tools now gets a `bash:` permission **pattern map**
   (`{"*": allow, "sed -i*": deny, ...}`, OpenCode's own last-match-wins glob syntax) instead
   of a flat `bash: allow`, using the identical dynamic disallowedTools check so both gates
   can never drift apart. `adapters/CODEX.md` and `adapters/HERMES.md` now say plainly,
   where they previously only said `disallowedTools` is "advisory", that neither harness has
   a per-agent equivalent available today and name the specific bypass mechanism, instead of
   leaving the gap implied.

   Stated honestly rather than overclaimed, in the script's own header and in both adapter
   docs: this is pattern-matching on the literal command string, not a sandbox -- it can miss
   obfuscated commands and can false-positive on a literal `>` inside a quoted search
   pattern (the fix there is to use the Grep/Glob tool instead of Bash, which this hook does
   not gate). It narrows the gap; it does not close it. Verified both new regression suites
   actually catch their failure mode: removed the hook's blocking logic, confirmed the exact
   2 expected `test-scripts.sh` failures, restored, re-ran green; separately removed
   `install-opencode.sh`'s pattern-map branch, confirmed the exact 1 expected failure,
   restored, re-ran green. 9 new regression cases (81 -> 90 assertions).

## [0.3.5] - 2026-08-18

### Added

1. **Never-auto-merge enforcement -- `templates/hooks/pre-push`.** Confirmed live via the
   engineering-manager's own forensic self-audit (it queried its harness's session-log
   database and found itself using Bash-invoked `Add-Content`/`sed -i` 8 times, directly
   violating its own `disallowedTools: Write, Edit, MultiEdit`): nothing in this repo
   deterministically enforced `human-checkpoint.md`'s canonical rule ("loops open PRs; they
   never merge"). A prior `loops.never_auto_merge` config key had already been deleted after
   being found under-wired, with no replacement mechanism put in its place -- the rule was
   prose only, restated in 11 agent files and enforced in none of them. `/sefi:init` now
   installs a POSIX `sh` `pre-push` git hook that refuses a direct push to `main`/`master`
   unless `SEFI_ALLOW_MAIN_PUSH=1` is set deliberately.

   Stated honestly rather than overclaimed: this is defense-in-depth, not the fix. Git never
   tracks `.git/hooks/`, so the hook is local-only and a Bash-capable agent can still route
   around it -- edit it, delete it, or run `git push --no-verify`, which skips hooks by
   design. The only backstop that survives that is a branch protection rule on the GitHub
   remote, which no tool available to an agent can configure; only a repo owner can set it in
   GitHub Settings. `human-checkpoint.md` now documents both the hook and this limit in one
   place instead of letting the hook imply more coverage than it has. Verified the regression
   tests actually catch the failure mode: re-broke the hook's blocking logic, confirmed the
   exact expected 3 failures (`main`, `master`, and a multi-ref push containing `main`),
   restored, re-ran green. 5 new regression cases (76 -> 81 assertions).

## [0.3.4] - 2026-08-18

### Added

1. **Agent visibility -- `mode:` written for every OpenCode agent.** Live-observed: with
   no `mode:` field, OpenCode defaults every agent to `mode: all` (Tab-cycle switchable
   AND dispatchable at once), so all 14 agents -- every specialist alongside
   `engineering-manager` -- sat in the same switcher as OpenCode's native `build`/`plan`
   agents, with nothing distinguishing the one entry point from the ones it dispatches. A
   direct switch to a specialist skips every gate that only runs on the dispatched path
   (`check-reply.sh`, `check-handoff.sh`, `ready-steps.sh`'s parallel cap) -- the same
   failure class as the `prompt-engineer` scope-creep bug `scope-boundary.md` exists for,
   just reachable through OpenCode's own UI instead of a direct prompt. `mode: primary`
   for `engineering-manager`, `mode: subagent` for the other 13, using OpenCode's own
   native field for exactly this distinction rather than inventing a workaround -- this is
   enforcement, not a restatement of the existing "always go through the EM" convention;
   the other 13 are now structurally absent from the switcher. Verified the regression
   test actually catches the gap (re-broke the fix, confirmed the exact failure, restored,
   re-ran green) and confirmed live: an actual install now shows exactly one `mode:
   primary` file among the 14. 1 new regression case (75 -> 76 assertions).

### Fixed

2. **`adapters/OPENCODE.md` contradicted itself.** Its own Install section still said
   `model:` "is dropped entirely, not preserved" -- the pre-`v0.2.4` behavior -- while its
   own "Model tiers and reasoning" section (written during the `v0.3.2` fix) correctly
   said the opposite. Missed during that fix because it only touched the section it was
   actively editing. Corrected to state the replace-not-drop behavior once, consistently.

## [0.3.3] - 2026-08-17

### Added

1. **Output-contract enforcement -- `scripts/check-reply.sh`.** Live failure: a
   `prompt-engineer` dispatch returned a full HTML/CSS document, the deliverable of
   `ui-ux-designer` and `software-engineer`, against a contract reading "Reply with exactly
   this digest and nothing else". A roster audit established why more prose was not the fix:
   that agent already carried the strongest defenses in the read-only set -- the tightest
   output contract, an explicit negative boundary, a machine-invoked clause, and a tool
   whitelist that HELD (no file was written; only content leaked). The whitelist governs file
   operations; nothing governed the reply. `per_agent_return_tokens` had sat in
   `config/budget.yml` since v0.2.1 read by no script -- a key `validate-config-wired.sh`'s
   own comment already named as a past example of decorative config, patched once to stop
   being orphaned and never actually wired. This wires it.

   The gate derives each agent's expected labels from its OWN `## Output contract` rather
   than a hand-kept parallel table, so the contract stays the single source of truth. Labels
   are matched only at the start of a line or bullet: qa-engineer's contract names
   "If REJECT:" and "If PASS:" mid-line as conditional branches, and ui-ux-designer's names
   per-mode branches, none of which are simultaneously required -- matching those would have
   failed every valid verdict. Exit 3 (CANNOT-CHECK) is distinct from 0 for agents whose
   contracts are table- or prose-shaped: reporting a pass for a check that never ran is the
   overclaim these gates exist to prevent, and a gate that cries wolf on valid replies trains
   its caller to ignore it. 6 new regression cases anchored on the real artifact
   (66 -> 72 assertions).

   **Hardened same-day by hunting further, not by trusting the first pass.** Probing beyond
   the shipped regression suite found two more gaps before this ever reached a tag: the
   reply-side label match was unanchored, so a label merely MENTIONED in prose ("I could not
   form a SUGGESTED: route because...") passed as if it were a real section -- fixed by
   anchoring it the same way extraction is anchored. And a single accurate verbatim quote of
   one plan heading (e.g. restating a constraint from a referenced plan) was rejected as a
   leaked plan on one marker hit -- fixed to require >= 2 of the 6 headings
   `validate-plan-structure.sh` already treats as one set, since correlated presence is real
   evidence and a lone quote is not. A third gap -- an agent with a malformed `tools:` line
   defaulting to read-only -- is documented in the script's own header as an accepted
   limitation rather than fixed: `validate-agents.sh` already requires every agent to
   declare `tools:` in CI, so the precondition has no live path to reach a CI-clean repo.
   3 more regression cases (72 -> 75 assertions).

2. **`skills/sefi-orchestration/references/scope-boundary.md`** -- the canonical
   produce-your-own-deliverable rule and its rationalization table, carrying the excuse
   observed live ("I have no write tool, so I'll produce the artifact inline instead") and
   its rebuttal: the missing tool is the boundary, not an obstacle to route around. One
   shared reference plus one-line links from the four read-only agents the audit found
   exposed (`prompt-engineer`, `engineering-manager`, `research-analyst`,
   `support-engineer`); four separate tables would have cost ~260 words against 149 of
   headroom, and this repo already resolves that with a canonical file plus links.
   `engineering-manager.md` item 3 now RUNS the gate instead of "discard excess" by eye.

   **Scope, stated rather than implied:** the gate covers the dispatched path, where an
   orchestrator exists to run it. A human invoking a specialist directly has no orchestrator
   in the loop, so nothing runs there -- and that is the path the live failure came through.
   `scope-boundary.md` says so plainly instead of letting the fix imply coverage it does not
   have.

### Fixed

3. **README's Proof block had drifted again** -- it claimed 65 assertions, 34 scripts, and
   8811 agent words while disk had moved past all three (v0.3.2 changed the suite without
   refreshing the pasted snapshot). Updated to the real output. Unlike the agent-count
   claims, this block is a pasted command result that no validator checks, since gating it
   would mean running the full suite inside a validator; it stays a manual refresh, named
   here so the gap is known rather than assumed closed.

## [0.3.2] - 2026-08-17

### Fixed

1. **OpenCode dispatch failed to resolve its own mapped model.** Live-observed by a real
   user's `engineering-manager` dispatch on OpenCode 1.18.18 (2026-08-07): every subagent
   dispatch failed, because `config/model-map.yml`'s `opencode:` block wrote a bare model id
   (`deepseek-v4-flash-free`) with no provider prefix. This is the exact failure class the
   v0.2.2/v0.2.4 fix already diagnosed and fixed for the Claude Code tier alias (`model:
   sonnet`) -- OpenCode resolves `model:` as a real `provider/model-id` and fails hard on
   anything less -- just never carried through to the replacement value that fix wrote in.
   Confirmed against OpenCode's own agent-frontmatter spec before changing anything: `opencode`
   is the provider segment for every OpenCode Zen model, and a bare model name is explicitly
   unsupported. Fixed to `opencode/deepseek-v4-flash-free` in all three tiers; a new
   regression test in `test-scripts.sh` asserts the emitted model carries a `/` provider
   prefix, verified to fail on the un-prefixed value before the fix and pass after.
   `adapters/CODEX.md` and `adapters/HERMES.md` were not touched -- Codex's own model ids are
   not provider-prefixed by convention, and Hermes consumes `deepseek-v4-flash-free` through
   its own `provider.model` config with no evidence of the same defect; extending an
   OpenCode-specific, live-verified fix to either would be exactly the kind of unverified
   claim this repo's anti-hallucination discipline forbids.

## [0.3.1] - 2026-08-16

Three drafted-and-gated plans, built. Each was validated by
`validate-plan-structure.sh` and left uncommitted-to-code deliberately, pending explicit
approval to build -- this release is that approval, executed.

### Added

1. **`prompt-engineer`, a 14th agent.** Runs as Stage 0 on an interactive human message,
   before the engineering-manager opens the routing table: restates a raw message into
   single-intent statements, surfaces only constraints actually stated, and attaches a
   non-binding suggested routing-table row. Tier `low` (haiku), read-only (Read/Grep/Glob,
   no Write/Edit/Bash) -- it restates, it never routes, plans, or persists. Reuses the
   existing `goal_intake` escalation (one question, then `needs-human`) rather than
   inventing a second clarification mechanism, and is skipped entirely on a
   non-interactive or scheduled trigger via the same flag `goal_intake` already honors.
   Boundary, stated in the agent file itself: prompt-engineer decides whether a request is
   clear enough to ROUTE; product-manager's goal_intake decides whether it is clear enough
   to PLAN -- if those two ever converge, delete the newer one. Self-funded: the word cap
   rises to 14 x 640 = 8960 against an unchanged 13-agent total of 8222 words, so no
   existing agent lost headroom. `skills/sefi-orchestration/references/roster.md`'s Growth
   note is corrected to match -- the flat folder holds through this addition as planned,
   and the NEXT one is what introduces a naming prefix or subfolders.

2. **The fan-out `morning-triage.loop.md`, `engineering-manager.md`, and `config/budget.yml`
   already declared.** `scripts/ready-steps.sh` computes the ready set from a plan's
   `(needs: ...)` markers -- the unchecked steps whose dependencies are all checked, capped
   at `max_parallel_worktrees` -- with 5 distinct exit codes (0 ready / 1 malformed / 2
   usage / 3 BLOCKED-cycle / 4 COMPLETE) so a caller can never mistake a stalled plan for a
   finished one. `engineering-manager.md` protocol item 5 now runs it instead of reasoning
   about markers in prose; `morning-triage.loop.md`'s Handoff names it as the dispatch-set
   source, and Verification is explicit that qa-engineer runs one pass per finding, never
   batched. `test-integration.sh` stage 3 exercises the real scheduler in place of the
   `grep -c '(needs: -)'` stand-in it shipped with. 7 new regression cases in
   `test-scripts.sh` (54 -> 61 assertions).

3. **`bar-comparison`, an optional qa-engineer evidence type.** Additive only, never a
   replacement for Done Criteria, and only when a real external artifact exists to judge
   against. `skills/anti-hallucination/references/bar-comparison.md` defines the
   Named/Fetchable/Comparable test, the blind protocol (the critic sees only the artifact
   and the bar, never the builder's report), and a binary MEETS_BAR/DOES_NOT_MEET_BAR
   verdict -- never a 1-10 score, since a similar critic-loop technique's own published log
   shows a score climbing 3.59 -> 5.05/10 across rounds while never once crossing its bar.
   `scripts/check-bar.sh` gates the envelope: a denylisted category label (award-winning,
   best-in-class, ...) is rejected, a local `source:` is checked for real, a URL's
   reachability is explicitly NOT verified (the plugin makes no network calls), and an
   empty `compare:` is rejected. `ui-ux-designer` AUDIT/REDESIGN is the mechanism's
   producer -- a consumer with no producer is the exact defect the memory vault already
   shipped once, not repeated here. Still bound by `max_retries` and both circuit
   breakers; explicitly does not adopt that technique's own uncapped "loop until wowed"
   design. 4 new regression cases in `test-scripts.sh` (61 -> 65 assertions).

All three plans above build to a single CI snapshot: 14 agents, 34 scripts parsing, 65 +
30 = 95 test assertions, 8811 of 8960 agent-budget words used. The Proof section below is
that snapshot, pasted from an actual run, not reconstructed from memory.

## [0.3.0] - 2026-08-11

A full-repo audit and the work it produced. Nine defects found, four documented-but-unbuilt
mechanisms shipped, every agent read against the mechanisms that changed under it, and the
whole loop skeleton executed end to end for the first time.

The pattern worth naming up front: almost every defect was in the EXECUTABLE layer, and most
were mechanisms this repo had already written down and not built -- or built and left
reachable by prose. Two were second occurrences of a bug class already fixed once elsewhere.
That is the argument for each landing as an executed regression test rather than a corrected
sentence. Validators 14 -> 16, assertions 7 -> 84.

### Fixed

1. **`budget-check.sh` failed open a second time.** v0.2.1 closed the "ccusage absent"
   branch; "ccusage present but broken" stayed open. A crash, an empty result, or a `null`
   was assigned straight to `spent`, and `awk -v s="null" '{print s+0}'` is `0` -- so an
   unreadable ledger certified every cap as within budget. Figures are validated before any
   arithmetic. Exit codes now separate EXCEEDED (1) from CANNOT MEASURE (3): under `set -e` a
   crashing ccusage previously aborted with a bare exit 1, indistinguishable from a real
   overrun to any caller reading only the code.
2. **`gate.sh` enforced no timeout at all**, while `loop-engineering/SKILL.md` shipped
   per-operation timeout classes as a predecessor-earned rule ("a 300s default killed a live
   12-task dispatch"). A hung suite hung the loop forever -- the same shape as the browser
   tool that ate a 50-iteration retry budget. Two classes now ship (default 300s, test 900s),
   expiry is named rather than surfacing as a bare exit 124, and a missing `timeout` binary
   is announced instead of implying a bound.
3. **`gate.sh` flag and coverage defects.** `npm test --silent` passed `--silent` to the test
   script rather than the runner. `shellcheck` globbed `./*.sh` unquoted and top-level only,
   so this repo's own scripts were never linted by its own gate. Added pnpm/yarn/bun
   detection, a typecheck step, `go vet`, `cargo fmt`, and a Makefile fallback.
4. **`compress-output.sh` could report a failure with zero diagnostics.** Output was filtered
   to lines matching `error|fail|exception`, so a tool failing with "2 tests did not pass"
   printed a FAIL line, a log pointer, and nothing else -- leaving the qa-engineer, the one
   agent meant to read it, with no diagnostic. Falls back to the output tail; a genuinely
   silent failure is labelled.
5. **`inject-memory.sh` injected the head of `index.md` rather than the router.** The
   `GENERATED:router` block starts at line 21 of the shipped template, so `head -n 40` spent
   roughly half the 1500-char budget re-sending frontmatter, the title and the folder list
   every session, then truncated the routing lines carrying the only signal. gen-router's
   durability ordering (v0.2.1) only pays off once the window holds router lines at all.
6. **The five-move loop gate was satisfiable by prose.** `grep -q Discovery` matches the word
   anywhere, so a spec with no section for any move passed the validator whose entire purpose
   is rejecting that. Anchored to the `## <Move>` heading in `validate-loops.sh` and
   `loop-readiness.sh`; a prose-only spec drops from 80/100 to 40/100. `validate-loops.sh`
   also now checks the project's own `loops/`, which this repo dogfoods and CI never read.
7. **`install-opencode.sh` stripped `model:` entirely**, and that quietly cost more than it
   saved. Dropping the field (v0.2.2) was right against a hard crash, but left every agent
   inheriting one session model -- so the qa-engineer judged the software-engineer on the
   IDENTICAL model. Generator/evaluator separation, this repo's first design principle,
   silently degraded to instructions-only. The installer now writes the mapped OpenCode model
   instead of deleting the field.
8. **`research-analyst` ran its own ad-hoc `if codegraph is on PATH` check** -- the exact
   pattern `probe-tools.sh` consolidates, with the same blind spot. On PATH is not working.
9. **Four agents described mechanisms that had changed under them.** `software-engineer` and
   `qa-engineer` now distinguish a gate TIMEOUT from a red gate (exit 124 is a measurement
   that never finished, evidence for neither verdict). `devops-engineer` owns budget plumbing
   and did not know about exit 3. `support-engineer` runs the triage Discovery move and did
   not know `probe-tools.sh` exists.

### Added

**`probe-tools.sh`** -- and with it, a claim the README had been making with no
implementation: "tools are probed before a loop may grant them". No probe existed anywhere.
The claim was also unbuildable as written (agent `tools:` frontmatter is granted by the
harness, not by a loop), so the mechanism was scoped to what is real -- external commands a
loop's moves shell out to -- and the README rewritten to describe it. Loops declare
`requires-tools:`, `validate-loops.sh` requires the line, and the probe reports four states
rather than two: presence is not health, and a binary that is installed and broken passes
`command -v` while failing the work. Offline by default; `--deep` opts in to credential
checks.

**`check-handoff.sh`** -- closing the asymmetry between plans and handoffs. Plans had
`validate-plan-structure.sh`; the handoff rule was enforced by nothing, despite failing more
expensively. A dispatch with a relative `writes:` path resolves against whatever working
directory the agent inherits, which is how a predecessor's task wrote to the user's home
directory and a reviewer approved the empty folder it was pointed at. Blocks a relative path,
an empty `reads:` or `context:`, a back-reference like "as discussed above", and an agent
slug resolving to no file.

**`state/retro-ledger.md`** -- the reversibility half of self-improvement. The retro loop
could apply bounded, qa-verified edits and keep no record, so it could re-edit the same file
weekly, re-propose something a human rejected, or leave a harmful edit in place forever.
Written at edit time (the `before` value exists only then) and carrying the commit SHA that
makes an edit revertible at all. Three read rules bind before target selection: churn guard,
rejection memory, evidence debt. The revert threshold is fixed now, while `state/metrics.md`
is still empty, because a threshold written after the numbers arrive is fitted to them.

**`references/close-out.md`** -- the memory vault's missing producer. `close_out` was
declared in every loop spec and defined nowhere, while `goal_intake` had a reference file.
The consequence was structural: `knowledge-manager.md` read `memory/daily/*.md` as "the raw
material", all twelve other agents filed observations as "a candidate for the
knowledge-manager", and no agent, hook or command ever wrote a daily note. `/sefi:init`
created `memory/daily/` and it stayed empty, so the weekly distill was a permanent no-op and
SessionStart had nothing to inject -- memory looked broken from both ends at once. It stays
an agent dispatch rather than a `Stop` hook because the privacy filter must run first, and a
deterministic hook cannot judge which bytes are a credential.

**`config/model-map.yml` and harness-neutral tiers.** Agents declare `tier:` (high/mid/low);
one table maps that to a concrete model and reasoning effort per harness. A new model,
rename, or harness is an edit there, never a pass over 13 agent files. `model-for.sh` is the
single reader; `apply-model-map.sh` serves harnesses whose install path has no transform
step. The literal `model:` stays beside `tier:` because the Claude Code plugin path reads
`agents/*.md` directly with no install step, so that value must be correct on disk --
`validate-model-map.sh` asserts the two agree.

**`.github/workflows/triage.yml`, installed at last** -- manual trigger only, cron present and
commented out. The loop spec had declared `cloud: cron 0 6 * * * via .github/workflows/triage.yml`
since the dogfooding scaffold, for a file never copied (the `/sefi:init` step is gated on
confirmation, and none was given -- commit 11346f9 recorded that correctly). Nothing surfaced
it afterwards, and it deadlocked the feedback apparatus: no scheduler, so no cycle; no cycle,
so no verdict; no verdict, so `state/metrics.md` stays empty; empty scorecard, so
`retro-improve` can never select a target; so the flip condition on `improvement.enabled`
("once weekly-retro has run a few cycles") was unreachable BY CONSTRUCTION rather than merely
unmet.

**The plan gains the fields three other agents were guessing at.** `product-manager` writes
the artifact the engineering-manager, software-engineer and qa-engineer all consume:
- *Slice sizing.* The software-engineer builds "exactly one plan slice" and nothing defined
  how big a slice may be, while `budget.yml` caps a dispatch at $0.15. The planner authors
  the work those caps must hold and had never been told they exist, so an oversized slice was
  a planning failure surfacing much later as a budget breach.
- *Dependency markers.* The EM's protocol says "sequence, do not parallel-guess" -- and a
  flat checkbox list gave it nothing to sequence FROM, so `max_parallel_worktrees: 3` was
  unusable without guessing. Steps now end with `(needs: N)` or `(needs: -)`.
- *Tool declaration.* Plans now carry `## Requires Tools`, with `none` as a deliberate
  declaration rather than a blank.

**`test-integration.sh`** -- the full loop skeleton, executed end to end in a real throwaway
git repo. Everything above was gated and validated but had never run in sequence, because no
loop has ever completed a cycle; by the qa-engineer's own delete-the-line test that made much
of it unwired. 30 assertions across 16 stages, in the order a real cycle runs them: scaffold
and the `.worktrees` check-ignore gate, tool probe deciding full vs reduced scope, a plan
passing its gate with `(needs: -)` markers parsed for parallel-ready steps, an envelope
passing the handoff gate, a budget preflight blocking a projected $0.30 dispatch against the
$0.15 cap BEFORE it runs, a real `git worktree` at the exact absolute path the envelope
pinned, a real slice built in it, `gate.sh` reporting PASSED (2 checks), the plan's Done
Criteria satisfied by EXECUTION, a grep-countable stop condition, a metrics row resolving to a
real managed-by file, `close_out` filing a note, `gen-router.sh` picking it up, the
SessionStart injection carrying it back out, a ledger SHA `git cat-file` confirms, and an
assertion that no merge commit exists.

Scale and install flows, previously untested: a 135-note vault still injects within the
1500-char cap with all 15 decisions surviving truncation (the durability ordering had only
ever run against 2 notes); 13 OpenCode agents convert with permission blocks and mapped
models, no surviving Claude alias, no leaked `tier:`; Codex writes sol/terra/luna by tier.
Workflow YAML is parsed rather than assumed, with `triage.yml` asserted manual-only.

**New validators.** `validate-model-map.sh` (tiers resolve to a model and a reasoning effort
on every harness; the literal `model:` matches the map; every shipped script passes `bash -n`
-- two live syntax errors in this batch came from an apostrophe inside an awk comment closing
the shell single-quote, invisible on reading and instant under `bash -n`).
`validate-links.sh` now also checks BARE filenames in prose, the surface the false README
claim slipped through on.

### Changed

- Codex maps to the GPT-5.6 family, web-verified: `gpt-5.6-sol` / `-terra` / `-luna`, a
  three-model line fitting the tiers exactly. Sol on `high` keeps the judge stronger than the
  generator. Recorded deadline: `gpt-5.4` and `gpt-5.4-mini` retire from Codex on 2026-08-31.
- OpenCode and Hermes on `deepseek-v4-flash-free`, web-verified (200K context, 128K output,
  free tier). Reasoning effort added per tier: Codex xhigh/high/medium, DeepSeek
  max/high/medium following its own "max for long agent loops" guidance. Claude Code has no
  per-agent dial, so its rows read `none` rather than blank.

### Deliberately unchanged

`security-engineer`, `solutions-architect`, `quant-analyst` and `ui-ux-designer` reference no
repo mechanism at all and are self-contained around their own subject matter; nothing in this
release changed under them. `technical-writer` was checked and left alone on purpose: its
item 4 already states the rule that would have prevented the false README claim. The failure
was that the rule was bypassed, not missing -- which is this repo's own thesis about gates
versus prose, demonstrated on itself, and why the fix was a validator rather than more prose
in an agent that was already right.

Agents total 7549 -> 8222 words against an unchanged 8320 cap.

### Still unproven, stated plainly

Every agent dispatch inside `test-integration.sh` is performed by the test harness. It proves
the machinery holds at the seams; it says nothing about whether a model decides well at them.
`state/metrics.md` still has zero rows, `improvement.enabled` is still false, the Codex and
OpenCode identifiers are web-sourced rather than dispatch-tested, and the triage workflow has
never executed on GitHub. The machinery is proven; the judgment is not.

## [0.2.2] - 2026-07-19

Hotfix: a real user running sefi-agents on OpenCode for the first time hit a hard failure
on every single subagent dispatch. First bug this project has had reported from actual
field usage rather than internal audit or testing.

### Fixed

- `install-opencode.sh` preserved every agent's `model:` line verbatim (e.g.
  `model: sonnet`) when converting for OpenCode. OpenCode does not treat this as an
  advisory hint the way Claude Code treats "sonnet" as a native alias -- it tries to
  resolve the value as a real provider/model identifier and fails hard:
  `Model not found: sonnet/`. Every one of the 13 agents carries a `model:` line, so this
  broke every subagent dispatch on OpenCode, not one. `model:` is now dropped entirely
  during conversion, so OpenCode falls back to the session's actual configured model.
- Observed alongside the bug, worth naming even though it is not this repo's own defect:
  when the specialized-agent dispatch failed, the orchestrating model did not stop and
  surface the error -- it silently fell back to an unconstrained generic subagent with
  none of the specialized agent's tool whitelist, output contract, or gate requirement.
  `adapters/OPENCODE.md`'s troubleshooting section now names this as a second problem
  worth stopping for, separate from the root-cause fix above.

### Added

- A regression test in `test-scripts.sh`: runs `install-opencode.sh` end-to-end against a
  temp destination and asserts `model:` is absent from the converted output while every
  other frontmatter field (tools/permission conversion, description, keywords) survives
  intact.

## [0.2.1] - 2026-07-16

Trust-bug batch: a behavioral audit found 11 cases where the repo stated a guarantee its
code did not deliver. All 11 closed, each independently reviewed (spec + quality, 0
Critical/Important), plus a final whole-branch review confirming cross-commit consistency
(also 0 Critical/Important; Ready to merge: Yes).

### Fixed

- `budget-check.sh` was fail-open: with no `ccusage` and no explicit `--spent`, it silently
  treated unmeasured spend as zero, so the shipped `triage.yml`'s "Enforce budget caps" step
  always passed regardless of actual spend. Now exits nonzero when there is no spend
  source; an explicit `--spent 0` remains a valid claim.
- `gen-router.sh` sorted all vault notes alphabetically, so `daily/` (trace notes) always
  preceded `decisions/` (durable notes); since the injection that reads this router
  truncates after ~16 lines, decisions were being silently evicted. Now emits notes in
  durability order (decisions -> entities -> projects -> other -> daily last).
- Six shipped agent/skill files contained references to other files that resolved to
  nothing (e.g. `ui-ux-designer.md`, `anti-hallucination/SKILL.md`, `retro-improve/SKILL.md`
  pointing at paths one directory short of the real file). All six fixed.
- `retro-improve`'s single-writer invariant held only within one project: a shared,
  user-global install let one project's self-improvement loop silently rewrite an agent
  file another project also loads. `/sefi:init` now asks whether an install is shared and
  defaults `improvement.enabled: false` (propose-only, not learning-off) when it is, or
  when the run is non-interactive.
- The `acting_on` loop-coordination lock was check-then-act (grep, then open a worktree),
  so two loops starting near-simultaneously could both find nothing claimed and both
  proceed. Now the claim is committed before the worktree opens, with git push rejection as
  the arbiter. Also: a crashed run's stale claim is now documented as clearable on resume,
  and a `git status --porcelain` preflight now runs before building.
- Three harness adapters (Hermes, OpenCode, Codex) implied or didn't clarify that
  `install.sh` never installs hooks -- so SessionStart memory injection only works via the
  Claude Code plugin path. One adapter's troubleshooting text actively implied a hook
  existed where none does. All three corrected.
- Five declared config keys were never read by any script or named as a rule:
  `memory.vault_dir`, `memory.inject_char_cap` (now both genuinely wired);
  `memory.prune_trace_after_days` (now a report-only threshold for the knowledge-manager,
  no auto-deleter); `per_agent_return_tokens` (now named in sefi-orchestration's
  output-contract rule); `loops.never_auto_merge` (deleted -- its name implied auto-merge
  was a toggle, contradicting the absolute rule in `human-checkpoint.md`, which is
  unchanged).
- `qa-engineer.md` now explicitly distinguishes `gate.sh`'s "no known toolchain detected"
  pass from a real "PASSED (N checks)" pass -- the former means nothing was checked, not
  that something was checked and passed, and must never be accepted alone as sufficient
  evidence for a slice that should have had a real toolchain.
- Three agents (`devops-engineer`, `qa-engineer`, `technical-writer`) had an Escalation
  clause with no time bound at all. All 13 agents now use the same explicit bound ("within
  2 minutes or this turn, whichever is sooner") the other 10 already used.

### Added

- `retro-improve/SKILL.md` now names a recurring routing-table miss as an explicit
  scorecard input, alongside qa-engineer REJECTs, gate failures, and contradictions.

- `validate-config-wired.sh`: CI gate asserting every declared config key is read by a
  script or named as a rule, checked over git-tracked files only.
- `validate-links.sh`: CI gate asserting every repo-path reference in shipped markdown
  resolves -- the reverse direction of the existing orphan-file check, which can only
  catch unwired files, never dangling references.
- `test-scripts.sh`: regression suite for the two behavior-changing fixes above, one
  assertion per audited failure mode plus the paths that must not regress.

## [0.2.0] - 2026-07-11

The software-company release: the roster becomes a 13-agent engineering org, five new
craft/gate skills land (including the cross-cutting anti-hallucination rule), and the
README is rewritten for the public launch.

### Added

- Agents (6 new): engineering-manager, devops-engineer, security-engineer,
  technical-writer, support-engineer, ui-ux-designer.
- Skills (5 new): anti-hallucination (the canonical no-invention rule every agent and
  skill points to), security-review (+ references/security-checklist.md),
  frontend-design (+ references/anti-slop-checklist.md), backend-design
  (+ references/api-checklist.md), technical-writing.
- Full-stack protocol in the software-engineer: vertical slices, contract-first at the
  API seam, backend-design below the seam, frontend-design above it.
- CI checks: validate-agents.sh and validate-skills.sh now require the
  anti-hallucination pointer line in every agent and skill.
- Repository CI workflow (.github/workflows/ci.yml) running the full validator suite on
  every push and pull request.

### Changed

- Roster renamed to software-company roles: researcher -> research-analyst, planner ->
  product-manager, implementer -> software-engineer, evaluator -> qa-engineer,
  librarian -> knowledge-manager, automation-architect -> solutions-architect
  (quant-analyst unchanged). All cross-references updated (routing table, roster,
  loops, docs, templates).
- validate-token-budget.sh: the agents/ word cap now scales with roster size
  (agent_count x 640) instead of the fixed 4,500.
- README rewritten as the public-launch page: evidence-first pitch, generic comparison
  with explicit edges, 13-agent / 12-skill tour, FAQ, and a no-invented-numbers
  commitment.

## [0.1.0] - 2026-07-11

Initial release: loop-engineered multi-agent plugin for Claude Code (also runs
on Hermes Agent, OpenCode, and Codex).

### Added

- `sefi-core` plugin: marketplace + plugin manifests.
- Agent roster (7): researcher, planner, implementer, evaluator, librarian,
  automation-architect, quant-analyst.
- Skills (7): sefi-orchestration, memory-protocol, loop-engineering,
  retro-improve, terse-mode, n8n-workflow-design, strategy-gate.
- Commands (5): init, triage, retro, status, loop-new.
- SessionStart hook that injects the memory router.
- Shell scripts: gate, compress-output, inject-memory, budget-check,
  gen-router, plus eight validators and their run-all entry point under `scripts/ci/`.
- Project templates copied by `/sefi:init`: memory vault, state ledger,
  inbox, two loop specs, config (sefi + budget), GitHub Actions workflow.
- Adapters for Hermes Agent, OpenCode, and Codex.
- Docs: LOOPS, ANTIPATTERNS, CHECKLIST, BUDGET, OPTIONAL-TOOLS.
- `install.sh` (human fallback) and `Install.md` (agent-targeted bootstrap).

[0.2.2]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.2
[0.2.1]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.1
[0.2.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.2.0
[0.1.0]: https://github.com/xsefirosus/sefi-agents/releases/tag/v0.1.0
