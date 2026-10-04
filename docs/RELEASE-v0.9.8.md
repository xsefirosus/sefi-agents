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
  directories, but Hermes' `skills/.hub/lock.json` is not part of that snapshot,
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
| `install-hermes.sh` (live) | exit 0 — 20/20 skills with verified source bytes, 13/13 commands registered |
| `install.sh --target claude` | exit 0 — hooks wired, `CLAUDE_PLUGIN_ROOT` set |

## Release status

**Pending.** The in-repo surfaces for 0.9.8 (changelog, this document) are
written, but there is **no `v0.9.8` tag, no GitHub release, and no marketplace
index entry**. The full `run-all.sh` aggregate must be green before a tag is
created, and publication requires separate, explicit release authorization.

Stage 2 — structured dispatch validation via `output_schema`, recoverable
checkpoints before destructive self-edits, and archive-instead-of-delete — is
**not implemented and not part of this release**.
