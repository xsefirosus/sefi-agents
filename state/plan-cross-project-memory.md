## Objective
Let one project's session read another related project's memory, without abandoning the
memory-protocol's existing project-local, git-committed vault. Today `memory/` lives only
inside each project's own repo (`memory-protocol/SKILL.md`), so two related projects on the
same machine cannot see each other's notes at all -- confirmed as a real gap, not assumed:
README's Memory section already states "no automatic sharing between two related
projects... no 'only show me what's relevant' filter today."

Add an OS-level shared mirror, additive to the existing vault, gated so it never runs where
it cannot be trusted:
- The project-local `memory/` vault stays exactly as it works today -- unchanged, still the
  single source of truth, still git-committed, still what every existing script and CI
  validator reads.
- On a real local machine only, the knowledge-manager's existing close_out write (memory-
  protocol WRITE step 2) is additionally mirrored to a per-OS-user shared folder, one
  subfolder per project, so a *different* project's session can find it later.
- On a detected ephemeral/cloud environment (this very session is one), the mirror step is
  skipped -- the project-local write still happens regardless, so nothing is ever lost to a
  container that gets wiped. Fail-safe direction: an environment we cannot positively
  confirm is a real local machine is treated as ephemeral, never the reverse.
- Reading another project's mirror is relevance-gated, not automatic: a session opens it
  only when the current request explicitly names or implies that other project. No
  background or session-start scan of the shared folder, ever -- this holds to the same
  "never bulk-load" rule the vault's own READ ladder already enforces
  (`memory-protocol/SKILL.md` READ step 1), just extended across projects instead of within
  one.

### Approaches weighed
- **Approach A -- OS-level shared mirror, relevance-gated read (CHOSEN).** Project-local
  vault untouched; a bash script resolves one shared path per OS user; the mirror write is
  best-effort and skipped outright on ephemeral environments. Cost: one new script, two new
  config keys, a write-side and read-side addition to memory-protocol. Matches the owner's
  explicit design (confirmed in conversation): folder per project, file per session, drive
  auto-selected (Windows: D: else C:; Linux: secondary mount else primary), per-OS-user
  scope, fallback to project-local memory on cloud containers.
- **Approach B -- replace project-local memory/ with the shared folder entirely (REJECTED
  by the owner).** Simpler (one write path, not two) but reverses three README claims
  verbatim ("in your project's own folder," "committed to your project's git repo,"
  no external settings folder) and drops git-commit visibility -- memory would no longer
  show in PR diffs or travel with a repo clone. Explicitly rejected in favor of the hybrid.

## Steps
- [ ] 1. Add `memory.cross_project.enabled` and `memory.cross_project.folder_name` config keys. (needs: -)
  `true` / `sefi-memory` defaults, in `plugins/sefi-core/templates/config/sefi.config.yml`
  and `config/sefi.config.yml`, with a comment naming the fail-safe default: ephemeral
  environments skip the mirror regardless of this flag; the flag only lets a user opt out
  entirely.
- [ ] 2. Write `plugins/sefi-core/scripts/resolve-shared-memory-path.sh`. (needs: 1)
  Prints the resolved shared-mirror root to stdout and exits 0, or prints nothing and exits
  1 when the mirror should not run. Logic, in order: (a) read
  `memory.cross_project.enabled`; if false, exit 1. (b) Ephemeral-environment check FIRST
  and fail-closed: if any of a short known list of CI/cloud/container markers is present
  (`CI`, `GITHUB_ACTIONS`, `CODESPACES`, `/.dockerenv`, or no real block device backing the
  filesystem the repo lives on) OR none of those can be checked conclusively, treat it as
  ephemeral and exit 1 -- uncertainty resolves to "skip," never to "write." (c) OS branch:
  on Windows (including Git Bash, this repo's tested Windows path per README's FAQ), test
  `/d` then `/c`; on Linux, parse `findmnt`/`/proc/mounts` for a mounted filesystem other
  than the repo's own root device, else fall back to the primary. (d) Compose
  `<drive>/<folder_name>/<os-username>/`, using `memory.cross_project.folder_name` from step
  1, and print it. Read-only probing throughout; this script never creates a directory
  itself -- the caller in step 4 does, only once it actually has content to write.
- [ ] 3. Wire a `.sefi/harness` install-time marker. (needs: -)
  `install.sh` writes it for `--target claude|hermes|opencode` (one line: the target name),
  and `plugins/sefi-core/scripts/install-hermes.sh` writes it too, since `adapters/HERMES.md`
  documents that as the separately-tested real Hermes install path. Add `.sefi/` to
  `.gitignore` -- this is a machine-local install fact, not a vault note, and does not
  belong in `state/` (which is git-committed) or the vault. Codex has no install script this
  repo controls (`adapters/CODEX.md`: marketplace path only) -- document the marker as
  UNKNOWN/absent there rather than inventing a Codex-side write.
- [ ] 4. Extend `memory-protocol/SKILL.md` WRITE section with a mirror step. (needs: 2, 3)
  After the existing privacy-filtered daily-note append (current step 2), call
  `resolve-shared-memory-path.sh`. On success, mirror the *same already-filtered* entry --
  never a second privacy pass on different content -- to
  `<resolved-path>/<project-slug>/<harness>-<topic>-<date-time>.md`, creating the project
  subfolder if absent. `project-slug` is the sanitized `git remote get-url origin`
  (owner-repo form) when available, else the sanitized absolute repo path, so two
  same-named repos from different remotes never collide. `<harness>` reads `.sefi/harness`
  from step 3, falling back to the literal `unknown-harness` if the marker is absent rather
  than erroring. `<topic>` reuses the daily entry's own topic slug -- no new derivation. On
  any failure to resolve or write the mirror (missing tool, permission denied, a sandbox
  that blocks writes outside the project directory), log one line and continue -- the
  project-local write already happened and is never blocked by this addition.
- [ ] 5. Extend `memory-protocol/SKILL.md` READ section with an explicit-relevance rung. (needs: 2)
  A session may resolve another project's slug (same derivation as step 4) under the shared
  root and open a specific matching note, but only when the current request names or
  clearly implies that other project by name -- never a scan of the shared folder's other
  subfolders, never at session start, and never as a fallback when the local vault simply
  lacks an answer. State this as a hard rule next to the existing "never bulk-load" line,
  not a separate policy. Same 2-wikilink-equivalent budget as local reads applies once
  inside the other project's note.
- [ ] 6. Update close-out.md to name the optional mirror step. (needs: 4)
  `skills/sefi-orchestration/references/close-out.md` so the close_out contract stays
  accurate about what the knowledge-manager's dispatch can now do.
- [ ] 7. Add 5 regression assertions to `test-scripts.sh`. (needs: 2, 3, 4)
  (a) with a CI-marker env var set, `resolve-shared-memory-path.sh` prints nothing and exits
  non-zero; (b) with no ephemeral markers and a fake writable drive path substituted in a
  temp `$HOME`/config, it resolves and is idempotent across two calls; (c) a fake git remote
  URL sanitizes to the expected project-slug with no path-unsafe characters; (d) a missing
  `.sefi/harness` falls back to `unknown-harness` without a nonzero exit; (e)
  `validate-config-wired.sh` passes with the 2 new keys from step 1.
- [ ] 8. Update the 3 adapter docs with the mirror's harness-neutral note. (needs: 4)
  `adapters/OPENCODE.md`, `adapters/HERMES.md`, `adapters/CODEX.md`: the mirror step is
  plain bash the knowledge-manager runs directly, so it needs no per-harness code -- state
  that once, and name the one real caveat: a harness or sandbox that disallows writes
  outside the project directory (this session's own remote container is a live example
  under investigation, not assumed) must make step 4's mirror fail closed, which it already
  does by design. Codex's entry additionally notes the harness marker is UNKNOWN there per
  step 3.
- [ ] 9. CHANGELOG entry and version bump. (needs: 4, 5, 7)
  Name the mirror, its fail-safe default, and the explicit-relevance-only read rule; version
  bump in `.claude-plugin/marketplace.json` (`metadata.version` and the `sefi-core` entry)
  and `plugins/sefi-core/.claude-plugin/plugin.json`.
- [ ] 10. README Memory section: rewrite to ~4 bullets. (needs: 9)
  Reflect the real mechanism -- project-local vault unchanged and still the source of
  truth; an optional per-OS-user mirror on real local machines only (never on cloud/CI);
  cross-project reads happen only when a request explicitly names the other project, never
  a background scan; the current "no automatic sharing... no filter today" claim is now
  inaccurate and must be replaced, not merely trimmed.
- [ ] 11. README "Why this exists": add a "Where these ideas come from" note. (needs: -)
  Graph engineering: direct match, cite `docs/ANTIPATTERNS.md`'s own "diamond pattern" line
  (split -> parallel workers -> a separate verifier node -> merge). Gauntlet Loop: same
  blind-critic/named-bar idea, but capped -- state the divergence (`bar-comparison.md`:
  PASS/REJECT under `max_retries`, never "loop until the critic is wowed") rather than a
  flat similarity claim. Kanban + CI/CD: one sentence (`max_parallel_worktrees` as a WIP
  limit, `state/`/`inbox/` as a pull board, CI with CD cut off at the PR on purpose).
- [ ] 12. README "How it compares": remove the "Beyond those three..." paragraph. (needs: -)
  Fully redundant with Safety rails bullets 1, 4, and 6.
- [ ] 13. README "The team": remove the reviewer-tier paragraph in full. (needs: -)
  Owner's explicit call -- including the `config/model-map.yml` sentence.
- [ ] 14. README "The skills": rephrase the section intro, drop the trailing paragraph. (needs: -)
  Fold in the current last paragraph's idea (some skills load automatically, some are
  called by name, and a named skill can never chain another named one -- so it cannot
  silently escalate commands), then delete that trailing paragraph.
- [ ] 15. Redraw `docs/assets/how-it-works.svg`. (needs: -)
  Fix the 3 confirmed label/arrow collisions ("results feed the scorecard" running into its
  arrowhead, "improves the agent above" colliding with the Applied box, "rejected" clipped
  off the left edge), and add the daily morning-triage loop as a column or row alongside the
  existing weekly-retro column -- it is currently entirely absent from the diagram despite
  being one of only two shipped loops. Render headlessly (Chromium `--screenshot`, as done
  for the current version) and visually inspect the PNG for overlap before treating this
  step as done -- an unverified render is PENDING, not passing.
- [ ] 16. README: add a closing paragraph summarizing both loops. (needs: 15)
  In "How a request actually gets done," sourced from `loops/morning-triage.loop.md` and
  `loops/weekly-retro.loop.md` (not written from memory), in the same section as the
  redrawn diagram.
- [ ] 17. README: delete "The loops" section, fold its unique content forward. (needs: 16)
  Delete "The loops (2 shipped, template for more)" and its Contents anchor entry, folding
  its two pieces of unique content into step 16's new paragraph: the five-required-elements
  rule and the `/sefi:loop-new` pointer.
- [ ] 18. README: add one sentence naming a proposed dependency-upkeep loop. (needs: -)
  support-engineer -> software-engineer -> qa-engineer, same PR-only pattern as the two
  shipped loops, as the answer to "what maintenance role is missing" -- prose only, not
  built in this plan.
- [ ] 19. Run full CI, paste the real tail into the final report. (needs: 7, 8, 9, 10, 11, 12, 13, 14, 17, 18)
  `bash plugins/sefi-core/scripts/ci/run-all.sh`, including the updated `test-scripts` count.

## Files Touched
config/sefi.config.yml; plugins/sefi-core/templates/config/sefi.config.yml;
plugins/sefi-core/scripts/resolve-shared-memory-path.sh (new); install.sh;
plugins/sefi-core/scripts/install-hermes.sh; .gitignore;
plugins/sefi-core/skills/memory-protocol/SKILL.md;
plugins/sefi-core/skills/sefi-orchestration/references/close-out.md;
plugins/sefi-core/scripts/ci/test-scripts.sh; adapters/OPENCODE.md; adapters/HERMES.md;
adapters/CODEX.md; CHANGELOG.md; .claude-plugin/marketplace.json;
plugins/sefi-core/.claude-plugin/plugin.json; README.md; docs/assets/how-it-works.svg

## Requires Tools
bash, git, awk, sed, grep, findmnt (Linux path; falls back to `/proc/mounts` if absent)

## Risks
- Sandbox write scope is the biggest open unknown, not a detail: some harnesses/hosts (this
  session's own remote container is one candidate) may disallow Bash writes outside the
  project directory entirely, independent of the ephemeral-environment check in step 2.
  Step 4 must fail closed on a permission error exactly like it fails closed on a detected
  ephemeral environment -- log and continue, never block the local write. This needs to be
  live-tested against at least one real sandboxed harness before Done Criteria, not assumed
  from reading docs.
- The ephemeral-environment marker list in step 2 is a known-list heuristic, not a proof --
  an undetected cloud environment could still attempt the mirror write. The fail-closed
  default on ANY uncertainty is the mitigation, not a guarantee; if a gap surfaces later,
  tighten the marker list rather than loosen the default.
- "Secondary drive" detection on Linux via `findmnt`/`/proc/mounts` is itself a heuristic --
  a mounted USB stick or a bind mount could be misread as a real secondary disk. Treat this
  as best-effort placement, not a guarantee of durability; the project-local vault remains
  the only guaranteed-durable copy.
- Relevance-gating (README step 10, memory-protocol step 5) depends on the model correctly
  judging "does this request name/imply another project" -- a prose judgment call, not a
  mechanical gate like `check-handoff.sh`. A future false-positive cross-project read is a
  retro-improve candidate, not something this plan can fully close mechanically.
- No prior note in `memory/decisions/` constrains this plan (vault checked before writing);
  the closest prior art is the existing project-local-only design this plan extends, not
  reverses.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` exits 0 with all validators passing and a
`test-scripts` count higher than before this plan by at least the 5 assertions in step 7.
`resolve-shared-memory-path.sh` run under a simulated CI env var prints nothing and exits
non-zero; run under a simulated non-ephemeral env with a fake drive present, it prints a
resolved path and does so identically on a second call. A fresh `bash install.sh --target
claude` against a throwaway `$HOME` produces `.sefi/harness` containing `claude`. The
redrawn `docs/assets/how-it-works.svg`, screenshotted headlessly, shows no label/arrow
overlap on visual inspection and includes the daily loop.
