# CI-WINDOWS-BASELINE

What the Windows failures actually were, and the rule for telling a real defect
apart from a fixture handing a native program an unreadable path.

Every item here was found by running the suites on Windows 11 / git-bash, not
inferred from reading the code.

## The one root cause

git-bash builds paths as `/c/Users/...`. Native Windows programs read that as
`\c\Users\...`, which does not exist.

| Native program | Symptom | Helper |
|---|---|---|
| python | `FileNotFoundError: C:\c\Users\...` | `scripts/sefi-python` |
| git | `fatal: cannot change to '/c/...'`, or **exit 0 and nothing created** | `scripts/sefi-native-path.sh` |
| jq | `jq: error: Could not open file /c/...` | `scripts/sefi-native-tool` |

Three properties made this expensive:

- **jq fails silently.** It returns empty output rather than erroring, so callers
  concluded a fixture was malformed instead of reporting the real error.
- **git can fail silently too.** `git worktree add` against an MSYS path exits 0
  and creates nothing — no diagnostic at all, just a missing directory.
- **Argument rewriting only covers `argv`.** A path carried inside stdin JSON
  cannot be rewritten by a wrapper. Two of the fixes below therefore changed the
  *producer* of a path, not the consumer.

All five helpers are committed `100755` and are no-ops on POSIX hosts.

## Fixture artifacts, not product bugs

Four failures looked like product defects. In each case the shipped code was
correct and the **fixture** was at fault. The test that established this was
always the same: run the *unmodified* script against both the native and MSYS
form of the input.

- **`install-codex.sh` marketplace identity** — aborted with `root is not a
  physical directory`. The check verifies marketplace identity and it was right:
  the real Codex CLI is a native program printing `C:/...`. Only the bash stub's
  MSYS echo failed. **Loosening that check would have weakened a real security
  property to satisfy a fake test**, so the stub was fixed instead.
- **`check-route.py` rollout discovery** — reported `sessions-dir-unavailable`
  for a `CODEX_HOME` that existed. A neighbouring case was passing *by
  accident*: a directory with no `sessions/` yields the same reason and would
  have masked the class.
- **`git worktree add`** — see the table above.
- **`test-integration.sh`** had adopted neither the path helper nor the
  telemetry stub, so it failed independently of everything already fixed.

## Environment-dependent assertions

**`ccusage` contamination.** `budget-check.sh` reads `ccusage` *before*
`--spent`, so on a machine with `ccusage` installed, assertions that pass an
explicit `--spent` measure the developer's real spend instead. Observed:
`source=ccusage` at 20.38 projected against an explicit `--spent 0`. Suites that
assert on budget must run under a stub that exits 0 while yielding **no usable
figure** — a stub exiting nonzero aborts the script under `set -e` and every
case returns 127. This bit two suites.

**`TMPDIR` must not be `/tmp`.** This MSYS build resolves `/tmp` correctly for
bash but a native tool handed the literal `/tmp/...` builds `C:\tmp\...`, which
does not exist:

| `TMPDIR` | `test-manifest-version.sh` |
|---|---|
| `$HOME/AppData/Local/Temp` | 54 pass, 0 fail |
| `/tmp` | 13 pass, **41 fail** — `root is not a directory: C:\tmp\...` |

It masquerades as product breakage: `create exits 0 (expected exit 0, got 2)`,
empty version, no commit recorded. **A large failure count on an otherwise-green
suite is the tell — check `TMPDIR` before believing a regression.**

**Terminal width.** `hermes skills list` truncates names at roughly 15
characters, so verification reported 10 of 20 installed skills as missing until
the installer set `COLUMNS`.

## Two rules for this repo

1. **Never edit source while a suite is running.** Drift-detection tests report
   the change by design and manufacture phantom failures.
2. **Read the whole log, not a mid-run snapshot.** A long suite takes many
   minutes; polling it early yields a flattering partial count. Grep the final
   log and the process exit code.

## Verifying shell-embedded Python

Two distinct hazards that fail in *different languages*:

1. `"$PY" -c '...'` is a **single-quoted shell string**. Bash terminates it at
   the first `'`, so a backslash or quote desyncs and you get `syntax error near
   unexpected token` **from bash, not Python**. `bash -n` still passes — it
   validates the file, not the function.
2. `<<'PY'` heredocs are not expanded by bash, so `\n` stays literal.

Exercise the **function**, not the file's syntax: run the failing entrypoint.
When a script that previously worked starts failing, `git checkout --` it before
investigating rather than patching forward from broken.

## Verified state

Individually green on Windows 11 / git-bash:

| Suite | Result |
|---|---|
| `ci/test-scripts.sh` | exit 0 — 288 pass, 0 fail |
| `ci/test-integration.sh` | exit 0 — 35 pass, 0 fail |
| `ci/test-manifest-version.sh` | exit 0 — 54 pass, 0 fail |
| `ci/test-prune-stale-skill-entries.sh` | 11/11, exit 0 |
| `ci/test-sefi-python.sh` | 6/6, exit 0 |
