# v1.0.0 Release Notes

Branch: `feat/cline-adapter` (PR to open; never merged by the author of this note)
Merged on: PENDING

## Scope

Cline becomes the fifth shipped harness, and the package version rolls to 1.0.0.
All work is Cline-focused; no other harness's installation path is changed by
this release beyond the shared validators that now cover five harnesses.

The root theme: Cline was already installed and live-verified on Cline Desktop
(agents/skills/commands/scripts under `~/.cline/`, always-on rules router, a
gated plan-to-design-to-build-to-judge cycle ending in a qa-engineer PASS), but
the repo represented it nowhere. This release promotes that local custom
installation into a `verified:shipped` adapter with manifest, docs, model map,
budget, route, and installer-test coverage.

## Added

### Cline adapter (`adapters/manifests/cline.yml`, `adapters/CLINE.md`)

Filesystem adapter, `verification:verified` / `support:shipped`. Cline runs
every tier on its configured model (`model_strategy: flexible`), dispatches via
the `spawn_agent` tool on Cline CLI/Desktop (the VS Code/JetBrains extensions
do not use subagents, per Cline's own docs -- out of scope by their statement,
not this repo's choice), and gets its always-on router from the
`~/.cline/rules/` global-rules auto-load rather than a session-start hook
(`hook_strategy: none`). Headless invocation, hook events, and task tracking
are UNKNOWN by design, never guessed. Install with
`install.sh --target cline --copy` (copy mode is load-bearing: symlink mode
cannot rewrite the plugin-root placeholder in file content).

### Model map, budget, route, and installer coverage

- `model-map.yml` gains a `cline:` block (every tier `flexible`,
  reasoning `none`); `check-route.py` short-circuits cline to
  `not-applicable`, like the other flexible harnesses.
- `budget-check.sh` accepts `--harness cline` (plus `$SEFI_HARNESS` and the
  `.sefi/harness` marker) with a `flat` default; the template comment,
  `docs/BUDGET.md`, `Install.md`, and the CI billing loops name all five
  harnesses.
- `harness-actions.md` gains a Cline column across the action, tool, and
  hook-event tables (dispatch = `spawn_agent`; UNKNOWN where unconfirmed),
  plus a route-evidence row (`not-applicable` via `flexible`).
- `test-install-cline-adapter.sh` (14 assertions), wired into `run-all.sh` and
  `test-ci-coverage.sh`. Pins the manifest contract, the `--adapter` refusal of
  a shipped manifest, a real `--target cline --copy` install into an isolated
  HOME (counts, coordinator body, package manifest, no placeholder), and the
  no-force refusal of a second run.

### Docs

README (badge, harness table, install prose), `Install.md` (detection,
billing defaults, audit invocation), `ADAPTERS.md` (shipped table),
`plugins/sefi-core/README.md` (audit invocation), `CHANGELOG.md` 1.0.0 entry.

## Tests

Full `run-all.sh` on Windows 11 / git-bash ran through `test-release-strict.sh` (the background runner was reaped before the aggregate line; the tail was verified piecewise). Every validator green except five schema assertions rooted in `jq` being absent on this host (schema validation requires jq; Linux CI has it) -- environmental, not product: `test-check-handoff.sh` 10 passed / 3 failed, two `check-reply.sh` schema cases failed. `test-release-strict.sh` exit 0 standalone; benchmarks 104 tests OK (2 skipped); shell syntax sweep over tracked shell files clean. Targeted gates green at
the time of this note: `validate-adapters` OK, `validate-budget` OK,
`test-design-council-routing` 16/16, `test-install-cline-adapter` 14/14,
`check-route.py cline high/mid` -> `not-applicable`, `model-for.sh cline`
-> `flexible`/`none`.

## Verification

`run-all.sh` green modulo the jq-absence schema assertions above; proceeding to the tag/release/ledger publication sequence.

## Scope boundaries

`v0.9.9` (`cdbb8b8`) and earlier tags are untouched.

This release covers the Cline adapter path. The `--force` full redo of a copy
install is pathologically slow on Windows git-bash (per-file `sed -i` spawn
over the skills tree); the installer test pins refusal-without-force rather
than a forced redo, and no installer code was changed for it.

## Version metadata

All five manifests read `1.0.0` at the time of this note (claude + codex
`plugin.json`, both `marketplace.json` occurrences, hermes `plugin.yaml`).
`git-tag`, `github-release`, and `github-marketplace-index` are recorded
`unobserved` in the ledger: no `v1.0.0` tag or release exists yet, and creating
either requires explicit human authorization.
