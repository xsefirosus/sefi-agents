# v0.9.9 Release Notes

Branch: `fix/0.9.9-hermes-skill-refresh` (PR #26), plus `docs/orchestration-load-semantics` (PR #25)
Merged on: 2026-10-10

## Scope

Windows/MSYS support for the Hermes install path, and five defects the full
suite exposed while verifying it. All work is Hermes-focused; no other harness's
installation path is assessed or changed by this release.

The root theme: on Windows, bash builds `/c/Users/...` paths that native Windows
programs cannot resolve. Python, `git`, and `jq` each failed in a way that looked
like a product bug but was a path-translation failure. Conversion now happens at
the native-tool boundary.

Argument rewriting only works for `argv`. A path carried inside stdin JSON cannot
be rewritten by a wrapper, which is why the producer of such a path is changed
rather than its consumer.

## Fixed

### `--auto-update` could not refresh an installed skill (`f2063ec`)

`hermes skills install` *skips* a skill that is already installed, so a refresh run
re-fetched nothing. The installer's own byte comparison then reported the
pre-existing content as a mismatch. Live failure: `--auto-update` refreshed the
managed runtime, left 2 of 20 skills stale, and exited 1 with `fetched skill
content differs from the expected source`.

`in_force` now returns true for every skill under `--auto-update`. A plain
first-time install is deliberately unchanged and still does not blanket-force, so
the community-skill scanner is not bypassed for all 20 skills on a fresh install.

### The version gate broke on every release bump (`69dffe9`)

`test-v09-documentation.sh` hardcoded the current version in 23 literals, so
bumping to 0.9.9 produced 4 FAILs. It now derives the version from `plugin.json`
and additionally asserts that all manifests agree. Historical changelog headings
stay pinned deliberately -- those assert release history, not the present version.

### A suite failed silently with exit 128 (`e5cdb26`)

`test-shared-memory-safety.sh` passed an MSYS path to native `git`, which cannot
resolve it. The suite aborted with **exit 128 and no diagnostic at all**, so the
aggregate reported `CI: FAILED` with zero FAIL lines, zero `ERROR:` lines, zero
`error(s)` summaries, and zero tracebacks. `run-all.sh` decides purely on exit
codes, so nothing in the log pointed at the cause.

This suite predates the MSYS work and is one of nine git-touching suites that never
received the path fix.

### Billing assertions read real telemetry (`d38999b`)

`budget-check.sh` reads `ccusage` first and only falls back to `--spent` when
ccusage yields no usable figure. The billing section asserts metered enforcement by
passing `--spent 999.00` against a 2.00 cap, but ~42 of its calls ran against the
developer's real `PATH` -- so they measured real local spend instead of the
fixture's number. On the host where this was found (ccusage 20.0.26) six metered
cases expected exit 1 and got 0 whenever real telemetry sat under the cap: **whether
the suite passed depended on how much the developer had spent that day.**

The section now exports `PATH="$EMPTYBIN:$PATH"` for its duration and restores the
caller's PATH at its end, so all calls see the empty stub. Verified the stub is
genuinely in effect: `command -v ccusage` inside the section resolves to the stub,
and a stubbed run reports `source=--spent`.

Left untouched on purpose, because they are *about* ccusage and manage their own
PATH: the "no ccusage + no --spent" case, the RDSTUB cases, and the FAKEBIN cases.

### A diagnostic comment tripped a validator (`b0fb804`)

The comment in `e5cdb26` quoted the failing path literally, and
`validate-no-personal-paths` matches `/Users/[A-Za-z0-9._-]+` -- where `...` is a
valid name. Reworded.

## Documentation

### Orchestration loading is per harness (`664823a`, `7c4a98d`)

The 0.9.8 notes described `sefi-orchestration` as "model-invoked" on every
harness. That is wrong: it is **session-loaded on three of the four**, so the
correction narrowed a claim that was largely correct rather than fixing a false
one -- while `adapters/CODEX.md` still said "every project loads
`sefi-core:sefi-orchestration` before work begins". The repo contradicted itself.

| Harness | Session-start event |
|---|---|
| Claude Code | `SessionStart` (`inject-orchestrator-role.sh`) |
| OpenCode | `session.created` |
| Codex | loads per project |
| **Hermes** | **none** |

Hermes is the only harness with no session-start event. Its shell hooks fire
solely on `pre_tool_call` and `post_tool_call` (verified in the Hermes source,
`agent/shell_hooks.py`), so there is no hook to copy across -- which is why that
row records Hermes as `UNKNOWN`.

The skill description and body now state this per harness. `adapters/HERMES.md`
records the gap and the reason, so a Hermes user is told plainly rather than
discovering it. `AGENTS.md` gains the routing role, because Hermes reads project
context files into the system prompt on every session -- the only always-on
mechanism it has. That is a prompt instruction, not a skill load, so
`/sefi-route` remains the deterministic path.

## Tests

`ci/test-install-hermes-refresh.sh` (12 assertions), wired into `run-all.sh`,
tracked `100755`. Pins both directions: every skill force-refreshed under
`--auto-update`, nothing force-installed without it. Asserts against the shipped
installer text as well as an extracted copy, so deleting the `AUTO_UPDATE` check
or bypassing `in_force` fails the suite. Mutation-checked: reverting the fix gives
11/1, bypassing `in_force` gives 11/1.

## Hermes install fixes

`install-hermes.sh --auto-update` writes `CLAUDE_PLUGIN_ROOT` to the Hermes `.env`
rather than requiring a hand edit, and prunes stale registry entries during
rollback. The Hermes plugin is staged *and enabled* -- a user plugin is disabled by
default, so copying the directory is not enough.

Two product defects in the Hermes plugin:

- Its content never reached the model. A plain handler return value is only printed
  to the terminal; delivery requires `PluginContext.inject_message`.
- Stale registry entries survived a rollback, so the next run reported every
  rolled-back skill as already installed.

## Verification

`bash plugins/sefi-core/scripts/ci/run-all.sh` on Windows 11 / git-bash:

- **142 sections, 493 passing, 0 failing, 0 tracebacks**
- **benchmarks: `Ran 104 tests` -- `OK (skipped=2)`**
- `test-scripts.sh` 337 PASS / 0 FAIL, exit 0 -- with the ccusage stub verified in effect
- `test-install-hermes-recovery-point.sh` 19/0, `test-sefi-archive.sh` 20/0,
  `test-sefi-recovery-point.sh` 18/0, `test-check-handoff.sh` 13/0, `test-sefi-python.sh` 6/0
- `validate-links` OK (105 files), `validate-doc-counts` OK (agents=17 skills=20
  commands=13 loops=3), `check-unicode-safety` OK (248 files)
- `validate-token-budget` OK (all within budget; agents total 10877 words)
- `validate-release-ledger` OK (latest 0.9.9)

Linux CI is the authority for cross-platform behavior. Both PRs merged with the
`validate` job green on Linux (`SUCCESS`), and this branch's Windows-specific work
is verified on Windows. Neither CI run exercises an MSYS-only code path.

## Scope boundaries

`v0.9.7` (`0e6c993`) and `v0.9.8` (`719f66b`) are untouched.

This release covers the Hermes install path. Installation capability for other
harnesses is outside its scope and is not assessed here.

## Version metadata

All four manifests are at `0.9.9`. `git-tag`, `github-release`, and
`github-marketplace-index` are recorded `unobserved` in the ledger because no
`v0.9.9` tag or release exists at the time of this note.