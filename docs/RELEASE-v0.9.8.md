# v0.9.8 Release Notes

Branch: rebased onto `origin/main` (base `983a2f4`, the divergence point)

## Windows/MSYS install support

The original scope was Hermes-only. It grew a second half because the
Hermes installer could not run on this host at all: four independent failures,
all one root cause.

git-bash builds paths as `/c/Users/...`. Native Windows programs read that as
`\c\Users\...`, which does not exist.

| Native program | Symptom | Helper |
|---|---|---|
| python | `FileNotFoundError: C:\c\Users\...` | `scripts/sefi-python` (rewrites path argv) |
| git | `fatal: cannot change to '/c/...'` | `scripts/sefi-native-path.sh` |
| jq | `jq: error: Could not open file /c/...` | `scripts/sefi-native-tool` |

`jq` was the dangerous one: it fails **silently**, returning empty output, so
callers concluded a fixture was malformed instead of reporting the real error.

Argument rewriting only works for `argv`. A path carried inside stdin JSON
cannot be rewritten by a wrapper — which is why two of the fixes below changed
the *producer* of a path rather than the consumer.

All five helpers are committed `100755` (`sefi-python` and `sefi-native-tool`
are exec'd as commands, not `bash <path>`), and each is a no-op on POSIX hosts.

## Hermes install fixes

Three real defects, all found while porting:

- **The `sefi-commands` plugin was never installed**, so `/sefi-init` did not
  exist even though the installer's own success message named it. A user plugin
  is disabled by default, so copying the directory is not enough — the installer
  now stages it and runs `hermes plugins enable`.
- **Plugin handlers' return values only print to the terminal.** Delivering a
  command to the model requires `PluginContext.inject_message`; a plain return
  value never reaches it.
- **Rollback left dangling registry entries.** Rollback removes skill
  directories, but Hermes' skill registry (the `lock.json` under its `skills/.hub`
  directory) is not part of that snapshot,
  so it kept entries whose directories were gone and the next run reported every
  rolled-back skill as already installed from a path that no longer existed.
  `prune-stale-skill-entries.sh` now prunes them: dry-run by default, `--apply`
  to mutate, a timestamped `lock.json.bak-<stamp>` written first, and a live
  skill directory never touched.

`CLAUDE_PLUGIN_ROOT` is recorded in the Hermes `.env` so the installed files
referencing it under `scripts/` stop silently no-opping (35 files in the managed
runtime). Note the Hermes
command is `/sefi-init`: Hermes slugifies the colon out of command names, so
`/sefi:init` does not survive registration.

Installer verification also read truncated skill names — `hermes skills list`
cuts at roughly 15 characters, which reported 10 of 20 installed skills as
missing until the installer set `COLUMNS`.

## Test-fixture corrections, not product changes

Two CI failures looked like product bugs and were not. Both were resolved by
fixing the fixture, because in both cases the shipped check was correct and
loosening it would have traded a real safety property for a green test.

**`install-codex.sh` marketplace identity.** The installer aborted with `root is
not a physical directory`. That check verifies marketplace identity and it was
right: the real Codex CLI is a native Windows program printing `C:/...` paths,
while the bash stub echoed back the MSYS form bash handed it. Established by
running the *unmodified* installer both ways — a native root passes the identity
check and proceeds to a later, unrelated assertion; only the MSYS form fails
this one. The stub now converts with `cygpath -m`.

**`check-route.py` rollout discovery.** Two assertions reported
`sessions-dir-unavailable` for a `CODEX_HOME` that demonstrably existed, for the
same reason. A native `CODEX_HOME` returns the correct
`invalid / rollout-ambiguous`. A neighbouring case was passing *by accident*: a
directory with no `sessions/` yields the same reason, so it would have masked
this class of failure.

One genuine test-isolation bug was also fixed in two suites:
`budget-check.sh` reads `ccusage` **before** `--spent`, so on a machine with
`ccusage` installed the assertions measured the developer's real spend — verified
`source=ccusage` at 20.38 projected against an explicit `--spent 0`. Both suites
now run under a stub that exits 0 while yielding no usable figure, so
`budget-check.sh` falls back to the explicit value.

`test-integration.sh` additionally missed the native-path fix entirely:
`git worktree add` against an MSYS path **exits 0 and silently creates nothing**,
so the worktree never appeared and the two stages downstream of it cascaded.

## Verified results

Measured on Windows 11 / git-bash, not estimated:

| Suite | Result |
|---|---|
| `ci/test-scripts.sh` | exit 0 — 288 passing, 0 failing |
| `ci/test-integration.sh` | exit 0 — 35 passing, 0 failing |
| `ci/test-manifest-version.sh` | exit 0 — 0 failing, 54 passing |
| `ci/test-prune-stale-skill-entries.sh` | 11/11, exit 0 |
| `ci/test-sefi-python.sh` | 6/6, exit 0 |
| `ci/test-check-handoff.sh` | 11/11, exit 0 |
| `ci/test-sefi-archive.sh` | 13/13, exit 0 |
| `ci/test-sefi-recovery-point.sh` | 18/18, exit 0 |
| `install-hermes.sh` (live) | exit 0 — 20/20 skills with verified source bytes, 13/13 commands registered |
| `install.sh --target claude` | exit 0 — hooks wired, `CLAUDE_PLUGIN_ROOT` set |
| **`run-all.sh` aggregate (final tree, T4)** | **exit 1 — 3 FAIL, 0 tracebacks** (log `C:\Windows\Temp\opencode\run-all-win-098-T4.log`) |
| **`benchmarks` unittest discovery** | **`Ran 104 tests in 521.359s` — `OK` (bare, no skipped count)** |

Exit-code derivation (sentinel absent, stated explicitly): the carrier
background task died after the terminal line and never wrote the `.exitcode`
file, so no recorded exit code exists. Exit 1 is accepted on verified
code-path evidence only: `plugins/sefi-core/scripts/ci/run-all.sh` lines
94–96 print `CI: FAILED -- one or more validators reported errors` if and
only if `$fail -ne 0`, immediately followed by `exit 1`; the sole other exit
is `exit 0` after `CI: all validators passed`. The log's terminal line is the
`CI: FAILED` line, so the run exited 1.

The 3 `FAIL` lines are all live `install-hermes.sh` in-runtime-symlink
assertions from `test-systems-audit-installers.sh` ("rejects an in-runtime
symlink after normal fetch validation", "names the post-copy runtime symlink
refusal exactly", "post-copy refusal restores the pre-install skill
sentinel"). Proven environmental, not slice-implicated: on this host `ln -s`
exits 0 but materializes a regular byte-identical copy (`[ -L ]` false, shown
by direct probe), so the unguarded fixture's link never existed and the
verifier passed a regular file, making the install succeed against
`expect_failure`. The guarded sibling case correctly reported PENDING, and the
T3 `install-hermes.sh` footprint (`rp_protect`/`rp_restore` wiring) cannot
produce installer success. Nothing was changed for these.

`ERROR` matches total 32: 30 inside PASS usage-error assertions, plus the
`docs-grounding.py finalize: error: ... required: --task, --manifest` line
(expected negative-path stderr inside `test-documentation-grounding-v091.sh`,
suite verdict PASS) and the terminal `CI: FAILED` aggregate line. `error(s)`
lines: 0. Real Python tracebacks (`Traceback (most recent call last)`): 0 —
bare `Traceback` hits are `no traceback` PASS assertions. Contrary to the
earlier expectation recorded here, `validate-no-personal-paths` is green on
this tree (`OK (no personal paths in shipped files)`); the pre-existing red
did not fire.

## Known findings not fixed in this release

**`validate-no-personal-paths` is red on `main`, and this branch does not fix it.**
`state/acceptance-v095-2026-10-01/installations/hermes/native-20261003.md` -- a
v0.9.5 Hermes install-evidence file committed in `fe22a31` -- quotes a real install
log path containing a literal username (`C:\Users\<user>\...`). The validator rejects
it. This branch has zero commits in that directory and the same content is present
on `origin/main`, so the red is pre-existing rather than introduced here. It is left
in place deliberately: the line is genuine install evidence, and rewriting recorded
evidence to satisfy a linter is the wrong trade. Fixing the release line is a
separate change against `main`.

**11 of 17 agents have no machine-checkable output contract.**
`check-reply.sh` derives its expected labels from an agent's `## Output contract`
section, and matches labels shaped like `^[A-Z][A-Z_]{2,}:`. Six agents declare
such labels (`prompt-engineer`, `qa-engineer`, `research-analyst`,
`security-engineer`, `ui-ux-designer`, and `systems-auditor` once its heading is
normalized). The remaining eleven describe their output in prose, so the script
exits 3 (`CANNOT-CHECK`) for them and runs only its word-count and
foreign-deliverable checks.

This is not a defect in the agents. All 17 run; a `3` is an explicit "unverifiable"
verdict, not a rejection, and the same fail-open shape `check-bash-write.sh` uses.
The gap is test coverage in a verification script. `systems-auditor.md` differs only
in kind: it declares four real labels under a nonstandard `## Reply and output`
heading, so they are invisible to the script. Normalizing agent contracts would
change what agents are told to emit, which is a behavioral change rather than a
documentation fix, and is out of scope for a Windows/MSYS release.

## Release status

**Published 2026-10-05.** Annotated tag `v0.9.8` on the PR 21 merge commit
`719f66b`, pushed to origin (`195f847f` `refs/tags/v0.9.8` peeling to
`719f66b`); GitHub release `v0.9.8` published (not a draft, not a prerelease)
2026-10-05T11:23:06Z:
https://github.com/xsefirosus/sefi-agents/releases/tag/v0.9.8.
Post-publication ledger evidence for all six surfaces is recorded in
`state/release-ledger.md` (0.9.8 rows, observed 2026-10-05T11:23:15Z).
Boundary, stated plainly: no `0.9.8` manifest bump landed in this release --
`plugin.json` (both manifests), `marketplace.json` (both occurrences), the top
`CHANGELOG.md` heading, and therefore the public marketplace index still read
`0.9.7` -- so per the release-tracking strict gate this release is only
partially complete at the six-surface level until a `0.9.8` bump lands. The
tag and the published release are real and verified above; neither `v0.9.7`
nor any other tag was moved.

## Stage 2 -- structured dispatch and recoverable destructive edits

Stage 2 shipped in three pieces, on top of the Windows/MSYS work above:

- **Optional `output_schema` on dispatch envelopes**
  (`plugins/sefi-core/scripts/check-handoff.sh`). `check-handoff.sh` already gated
  agent/reads/writes/budget/context, but nothing stated what the dispatched agent
  must put in the directory `writes:` names. The new optional field names a JSON
  Schema the returned labels must satisfy; an envelope without it behaves exactly
  as before. The gate refuses a relative schema path, a schema path that does not
  exist (an unreadable schema fails open at return time, so the dispatch would
  read as checked while nothing is checked), invalid JSON, and valid JSON with no
  `required` labels. Whether a reply matches the schema is a return-time check and
  stays with `check-reply.sh`. New suite
  `plugins/sefi-core/scripts/ci/test-check-handoff.sh` (11 assertions, exit 0).
- **Archive before delete** (`plugins/sefi-core/scripts/sefi-archive.sh`, wired
  into the `install-opencode.sh` `--force` path). `install-hermes.sh` already
  quarantined skills before rollback; `install-opencode.sh` reached the same
  `rm -rf` with no copy at all, so a mistaken `--force` destroyed hand-edited
  files with no way back. The shared helper archives first
  (`sefi_archive_init` / `sefi_archive_put` / `sefi_archive_restore` /
  `sefi_archive_purge`), refuses symlinked targets, and records absent paths so
  rollback is exact. Verified live, not only by unit test: a `--force` install
  into a temp home, a hand-edit appended to an installed agent, then an
  interrupted second `--force` run left the surviving archive holding the
  hand-edited content (15 entries recorded); a clean `--force` install returns 0
  with 17 agents and no leftover archive. New suite
  `plugins/sefi-core/scripts/ci/test-sefi-archive.sh` (13 assertions, exit 0).
  Linux CI run 37227459297 caught one regression from this piece (the
  unconditional archive refusal broke the swapped-symlink replace path); the fix
  guards the archive call on a non-symlink target, since `rm -rf` on a link
  removes the link without dereferencing it.
- **Named recovery points** (`plugins/sefi-core/scripts/sefi-recovery-point.sh`).
  The archive is anonymous and run-scoped: init, put, restore, purge, all in one
  process, gone when it ends. A recovery point is named and persists across
  processes, so a rollback can happen minutes or days later, and it is never
  auto-purged -- discarding is explicit (`rp_create` / `rp_protect` / `rp_list` /
  `rp_restore` / `rp_discard`). Not wired into any caller yet: it is the
  mechanism, and the call site is a separate decision. The name is deliberate:
  "checkpoint" already means the human PR boundary
  (`skills/sefi-orchestration/references/human-checkpoint.md`), so a second thing
  called a checkpoint would collide in prose and in anyone's reading of a log
  line. New suite
  `plugins/sefi-core/scripts/ci/test-sefi-recovery-point.sh` (18 assertions,
  exit 0).

All three Stage 2 suites are green on Linux CI (run 37229227815) and exit 0
under this host's git-bash.

## Correction -- 2026-10-05 (append-only; everything above left as published history)

The "Release status" section above states at lines 180-186 that no `0.9.8`
manifest bump landed, that `plugin.json` (both manifests), `marketplace.json`
(both occurrences), the top `CHANGELOG.md` heading and therefore the public
marketplace index still read `0.9.7`, and that the release is accordingly only
partially complete at the six-surface level until a `0.9.8` bump lands.

Those lines remain true of the **published** release: the tag `v0.9.8` was cut
on `719f66b`, and that tree carries no `0.9.8` manifest bump, which is exactly
what the published GitHub release body says. They are **stale about this tree**.
The `0.9.8` manifest bump landed afterwards, on the `release-0-9-8-bump`
worktree, and is recorded append-only in `state/release-ledger.md` as
superseding observations observed 2026-10-05T12:01:14Z. On the current tree:

- `plugins/sefi-core/.claude-plugin/plugin.json` and
  `plugins/sefi-core/.codex-plugin/plugin.json`: `0.9.8`
- `.claude-plugin/marketplace.json`, both `metadata.version` and
  `plugins[0].version`: `0.9.8`
- `CHANGELOG.md` first versioned heading: `## [0.9.8] - 2026-10-05`
- the public marketplace index still reads `0.9.7` at the time of writing, so
  `github-marketplace-index` is the one surface where a `0.9.8` bump has not
  reached the public surface; `git-tag` and `github-release` carry `0.9.8`
  matches (see the ledger rows for both).

Consequence for the strict gate: the six-surface completion state changed after
publication, and the text above is superseded for current trees. Nothing above
is edited: the tag, the release, and the ledger's earlier rows are history.