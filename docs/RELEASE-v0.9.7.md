# v0.9.7 Release Notes

v0.9.7 replaces the single `metered` missing-key default with per-harness
billing defaults. `budget-check.sh` resolves `opencode` and `hermes` to `free`,
and `codex` and `claude-code` (`claude` is accepted as an alias) to `flat`,
when the config carries no `billing_mode` key. No harness signal, or an
unrecognized one, resolves `metered` -- fail-closed. `metered` becomes opt-in:
`billing_mode: metered`, explicitly. A defaulted skip names its source
(`skip scope=... billing_mode=... (per-harness default; ...)`). The release
remains local-first, offline-testable, and dependency-free.

## Harness resolution order

An explicit `billing_mode` always wins. When the key is absent, the harness
comes from `--harness`, then `$SEFI_HARNESS`, then the machine-local
`.sefi/harness` marker written by `/sefi:init`. Measured behavior on a keyless
config, `budget-check.sh --harness <name> --scope daily --spent 999.00`
against the 2.00 daily cap: `opencode` and `hermes` exit 0 with a recorded
`billing_mode=free` skip; `codex` and `claude-code` exit 0 with a recorded
`billing_mode=flat` skip; no harness signal exits 1 (EXCEEDED, enforced).

## Stricter edges around the default

- A `billing_mode` key that is present with no value is a usage error (exit 2)
  in both `budget-check.sh` and `validate-budget.sh`: absent is absent, empty
  is invalid. Reading empty as "use the default" would have silently
  downgraded a metered install to a skip.
- `--harness` rejects a following flag as a missing value
  (`budget-check: --harness requires a value (got flag '--config')`) instead
  of consuming it as a harness name; the same check covers every value-taking
  flag.
- A `.sefi/harness` marker that cannot be read is handled explicitly: the read
  is guarded, the case is reported, and the default falls back to `metered`
  (fail-closed).
- The accepted `claude` alias and the empty-value rule are documented in
  `docs/BUDGET.md`, `Install.md`, `plugins/sefi-core/commands/init.md`,
  `config/budget.yml`, and the shipped `templates/config/budget.yml`.

Fixture coverage in `test-scripts.sh` pins the per-harness defaults, the
empty-value cases, and the argument-parsing cases. See `docs/BUDGET.md` for
the authoritative spend-mode table.

## Correction to the published v0.9.6 entry

The v0.9.6 entry (and its GitHub release body, which is that same text) states
that a config predating the `billing_mode` key defaults to `metered`. That was
v0.9.6 behavior and is superseded for current trees by the per-harness rule
above. The v0.9.6 entry itself is preserved byte-for-byte as published
history; nothing else in it changes.

## Evidence recorded

v0.9.5 native-legs install evidence under
`state/acceptance-v095-2026-10-01/installations/`: the 20261002 round
(`claude`, `codex`, `hermes`, and `opencode` native install logs, per-leg
status notes, environment probes, `INCIDENT-native-20261002.md`) and the
20261003 round (`codex`, `hermes`, and `opencode` native logs with per-leg
notes, a budget-flat fixture, and a metrics-ledger line recording the
billing-harness-defaults merge QA PASS). Evidence only; no behavior change.

## Release status

This working tree is partially released for v0.9.7: the in-repo surfaces
(manifests, changelog, ledger) are reconciled, while the tag, GitHub release,
and marketplace index remain unobserved. Local CI and fresh-install fixtures
must pass before a tag, GitHub release, or marketplace update is created.
Publication requires separate, explicit release authorization and evidence.
