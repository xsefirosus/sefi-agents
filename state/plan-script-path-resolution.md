## Objective
Fix a real gap found live by another session running this repo's own `main`: 24 prose
instructions across agents/skills tell an LLM to "run scripts/X.sh" as a bare relative
path with no stated resolution rule, and neither `install.sh` nor `install-opencode.sh`
ever copies `plugins/sefi-core/scripts/` into an installed destination at all. Verified
directly (not taken on the other session's word): read both installers end to end,
confirmed neither touches `scripts/`; confirmed via a claude-code-guide lookup against
official docs that `${CLAUDE_PLUGIN_ROOT}` is inline-substituted by Claude Code's native
plugin loader anywhere it appears in loaded agent/skill markdown (the same mechanism
`hooks/hooks.json` already relies on for its two hook scripts) -- but that substitution is
specific to the native `/plugin install` path, not to `install.sh`'s own "human fallback
for non-plugin runtimes" (its own header's words) targets.

## Steps
- [x] 1. Prefix every bare `scripts/<name>.sh` occurrence in `plugins/sefi-core/agents/*.md`
  and `plugins/sefi-core/skills/**/*.md` with `${CLAUDE_PLUGIN_ROOT}/` (24 occurrences
  across 14 files, enumerated by
  `grep -rn 'scripts/[a-zA-Z_-]*\.sh' plugins/sefi-core/agents plugins/sefi-core/skills`).
  This fixes the primary, README-documented install path (`/plugin marketplace add` +
  `/plugin install`) completely and correctly -- confirmed by official Claude Code docs,
  matching the exact pattern `hooks.json` already uses successfully. (needs: -)
- [x] 2. `install.sh`: add `scripts` to the `for sub in agents skills commands` loop so the
  claude-fallback and hermes targets get it symlinked/copied too. When `--copy` mode is
  used, additionally run a substitution pass over the copied `agents/skills/commands`
  files replacing the literal string `${CLAUDE_PLUGIN_ROOT}` with the resolved absolute
  `$DEST`, so a copied install carries working literal paths with no runtime substitution
  required. Symlink mode (the default) cannot do this without mutating the source
  checkout -- state that limitation plainly in the script's own header comment rather than
  silently leaving it unfixed-and-unstated: scripts/ becomes reachable via the symlink, but
  the `${CLAUDE_PLUGIN_ROOT}` placeholder stays literal for a non-plugin symlinked install.
  (needs: 1)
- [x] 3. `install-opencode.sh`: add `scripts` to the required-source-dir check and copy it
  via a new `copy_dir "$SCRIPTS_SRC" "$DEST/scripts" "script"` call (always-copy, matching
  its existing never-symlink behavior). Add a substitution pass -- `sed` replacing
  `${CLAUDE_PLUGIN_ROOT}` with the resolved absolute `$DEST` -- applied to every file
  `transform_agent` writes and every file `copy_dir` copies for skills/commands, so
  OpenCode installs end up with real, resolved, literal paths and need no runtime
  understanding of the placeholder at all. (needs: 1)
- [x] 4. New validator `scripts/ci/validate-script-refs.sh`: greps every agent/skill `.md`
  for a `scripts/[A-Za-z0-9_-]+\.sh` occurrence NOT immediately preceded by
  `${CLAUDE_PLUGIN_ROOT}/`; any hit is an unresolvable bare reference and fails the build.
  Wire it into `scripts/ci/run-all.sh`'s validator list, after `validate-links.sh` (same
  ordering rationale: `validate-links.sh` already proves paths resolve on disk; this new
  check proves the SAME references resolve when read by a dispatched agent instead of by
  a linter walking the repo tree -- the exact distinction this whole gap turned on).
  (needs: 1)
- [x] 5. Regression tests in `scripts/ci/test-scripts.sh`: (a) a bare `scripts/x.sh`
  reference with no prefix is flagged by the new validator; (b) a correctly-prefixed
  `${CLAUDE_PLUGIN_ROOT}/scripts/x.sh` reference passes clean; (c) running `install.sh
  --copy --target hermes` against a temp `$HOME`/`$HERMES_HOME` places `scripts/` at the
  destination and leaves no literal `${CLAUDE_PLUGIN_ROOT}` string in any copied `.md`;
  (d) running `install-opencode.sh` against a temp `$OPENCODE_HOME` does the same. At
  least 6 assertions, exercising the real scripts against real temp directories, not
  simulated. (needs: 2, 3, 4)
- [x] 6. CHANGELOG entry naming the two-part nature of the fix (prose prefix for the native
  plugin path; installer copy + substitution for the fallback paths) and the honest
  symlink-mode limitation from step 2. `README.md` Proof block refreshed to the real
  post-fix `run-all.sh` counts. (needs: 5)
- [x] 7. Run `run-all.sh` in full. (needs: 6)

## Files Touched
plugins/sefi-core/agents/*.md (8 files with hits); plugins/sefi-core/skills/**/*.md (6
files with hits); install.sh; plugins/sefi-core/scripts/install-opencode.sh;
plugins/sefi-core/scripts/ci/validate-script-refs.sh (new);
plugins/sefi-core/scripts/ci/run-all.sh; plugins/sefi-core/scripts/ci/test-scripts.sh;
CHANGELOG.md; README.md

## Requires Tools
bash, sed, grep, git

## Risks
`${CLAUDE_PLUGIN_ROOT}` substitution for a manually-symlinked (non-plugin) Claude Code
install is NOT solved by this plan -- it cannot be, short of exporting a persistent
environment variable into the user's own shell profile, which an installer should not do
unasked. This is stated as a known limitation, not silently left implied-fixed: symlink
mode gets the FILES (scripts/ is now reachable) but not guaranteed-resolving PROSE
references. Only `--copy` mode (and OpenCode, which is always copy) gets the full fix.
The README's own documented primary install path (`/plugin marketplace add` +
`/plugin install`) is unaffected by any of this -- it was already broken before this plan
and is fully fixed by step 1 alone, confirmed against official docs rather than assumed.
Second risk: `validate-links.sh`'s existing reference-extraction regex
(`(docs|skills|scripts|...)/[A-Za-z0-9._/-]+\.(md|sh|...)`) matches `scripts/x.sh` as a
substring regardless of what precedes it, so prefixing references with
`${CLAUDE_PLUGIN_ROOT}/` does not break that existing validator -- confirmed by reading
its regex before editing, not assumed; re-verify with a live `run-all.sh` pass in step 7
rather than trusting this reasoning alone.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with the new
`validate-script-refs.sh` wired in and green; zero bare (unprefixed) `scripts/*.sh`
references remain in `plugins/sefi-core/agents/*.md` or `plugins/sefi-core/skills/**/*.md`;
`install.sh --copy --target hermes` and `install-opencode.sh`, each run against a real
temp directory, produce a `scripts/` directory at the destination containing the
referenced scripts, with zero literal `${CLAUDE_PLUGIN_ROOT}` strings left in any copied
`.md` file; `validate-links.sh` still passes clean, proving the new prefix did not break
existing link resolution.
