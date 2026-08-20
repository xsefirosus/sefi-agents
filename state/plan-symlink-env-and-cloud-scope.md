## Objective
Close two of the three items from the "known permanent limits" review: (1) `install.sh`'s
default symlink-mode install leaves `${CLAUDE_PLUGIN_ROOT}` unresolved in agent/skill
prose -- turns out NOT permanent, confirmed via official docs that `settings.json`
supports a persistent `"env"` key exported to every Bash tool call, so setting
`CLAUDE_PLUGIN_ROOT` there resolves the placeholder via ordinary shell expansion with zero
file-content rewriting; (2) state honestly, in `install.sh`'s own header, that its
`wire_claude_settings()` hook/env wiring protects a local terminal CLI install but not a
cloud/remote ("Claude Code on the web") session -- confirmed via official docs that cloud
sessions do not read `~/.claude/settings.json` at all, only a project-level
`.claude/settings.json`. Item 3 (Hermes hooks) needed no change: already correctly
documented as `UNKNOWN`/gates-are-the-real-enforcement in `adapters/HERMES.md` and
`skills/sefi-orchestration/references/harness-actions.md`. Item 4 (skill naming pass) is
explicitly deferred, not part of this plan.

## Steps
- [x] 1. Rename `wire_hooks_claude()` to `wire_claude_settings()` in `install.sh` (its scope
  is broader now); extend it to also merge `{"env": {"CLAUDE_PLUGIN_ROOT": "$DEST"}}` into
  `$DEST/settings.json` via the same `jq` merge pattern already used for `hooks` --
  additive, preserves any pre-existing unrelated `env` keys, idempotent on re-run (same
  proof obligations as the existing hooks merge). Runs for `--target claude` regardless of
  `MODE` (symlink mode is exactly the case this closes; copy mode already resolves the
  placeholder in file content, so setting the env var there too is redundant but harmless,
  not harmful -- consistency over cleverness). (needs: -)
- [x] 2. Update `install.sh`'s header comment: the symlink-mode limitation stated in the
  0.3.13 comment block is no longer accurate for the `claude` target specifically (the env
  var closes it) -- correct that comment rather than leave a now-false claim standing.
  State plainly instead: `wire_claude_settings()` (hooks + env) protects a LOCAL TERMINAL
  CLI install; a cloud/remote session does not read `~/.claude/settings.json` at all
  (confirmed against official docs, not assumed) and needs a project-level
  `.claude/settings.json` instead, which this installer does not create -- a stated scope
  boundary, not silently implied-fixed. (needs: 1)
- [x] 3. Regression tests in `scripts/ci/test-scripts.sh`: (a) after a symlink-mode install
  (the default, no `--copy`), `settings.json`'s `env.CLAUDE_PLUGIN_ROOT` is set to the
  resolved `$DEST` -- proving the fix actually targets the mode that needed it; (b) a
  pre-existing unrelated `env` key survives the merge untouched, same merge-safety
  discipline as the existing hooks test; (c) idempotent on a second run (no duplication --
  trivial for a scalar env value, but assert it explicitly rather than assume); (d) the
  jq-missing path still warns and does not corrupt `settings.json` (extend the existing
  no-jq assertion rather than duplicate it). At least 4 new assertions. (needs: 1)
- [x] 4. Run `run-all.sh` in full; CHANGELOG entry naming both the fix (env var closes the
  symlink-mode gap, confirmed via docs) and the honest scope correction (cloud sessions
  need project-level settings.json, which this installer does not provide). (needs: 2, 3)

## Files Touched
install.sh; plugins/sefi-core/scripts/ci/test-scripts.sh; CHANGELOG.md; README.md

## Requires Tools
bash, jq, sed, grep

## Risks
The `"env"` key's exact precedence/scope rules (managed > local > project > user, per the
docs lookup) mean a project-level or managed setting could still override a user-level
`~/.claude/settings.json` env value this installer writes -- stated as a real possibility,
not silently assumed away, though it does not change the fix's correctness for the common
case (no competing project-level override present). Second: this plan does not add
project-level install support for cloud sessions -- that is a separate, larger feature
(install.sh has no concept of "the current project" today) and is explicitly out of scope
here; item 2 documents the gap rather than closing it.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with the new assertions; a fresh
symlink-mode `install.sh --target claude` run against a real temp `$HOME` produces a
`settings.json` with `env.CLAUDE_PLUGIN_ROOT` set to the resolved destination path, proven
via `jq`, not asserted; the merge-safety and idempotency proofs from the existing hooks
tests are matched for the new env key; `install.sh`'s header no longer claims the
symlink-mode placeholder gap is unconditionally unresolved.
