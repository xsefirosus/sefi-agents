# v0.9.6 Release Notes

v0.9.6 adds metered-versus-flat spend-mode switching for installs.
`config/budget.yml` (and the shipped template) declares `billing_mode` --
`metered`, `flat`, or `free`. Dollar caps enforce only on `metered`; on `flat`
or `free` the dollar-cap checks skip with a recorded reason. Everything that is
not a dollar cap stays always on regardless of mode. The release remains
local-first, offline-testable, and dependency-free.

## Spend modes (`billing_mode`)

A config that predates the `billing_mode` key defaults to `metered`,
preserving current behavior. `validate-budget.sh` rejects any other value as a
usage error. Fixture coverage in `test-scripts.sh` pins the switch: metered
enforcement is unchanged, `flat` and `free` skip with a recorded reason, a
missing key defaults to metered, metered exit-3 (CANNOT MEASURE) semantics are
unchanged, and unknown modes or scopes remain usage errors.

## Dollar-scope gating

On `flat` or `free` plans `budget-check.sh` exits 0 with a recorded skip
reason (`skip scope=... billing_mode=...`) instead of enforcing
`per_run_usd_cap`, `daily_usd_cap`, or `per_dispatch_usd_cap` -- so
ccusage-imputed dollars on free usage never block work over money that was
never spent.

## Always-on discipline

Switching to `flat` or `free` silences only the dollar scopes. Retry caps,
reply caps, worktree caps, the minimization ladder, and the token-discipline
stack in `docs/BUDGET.md` stay always on -- discipline does not sleep. See
`docs/BUDGET.md` for the full spend-mode table and rationale, and `Install.md`
for the install-guide summary.

## Release status

This working tree is partially released for v0.9.6: the in-repo surfaces
(manifests, changelog, ledger) are reconciled, while the tag, GitHub release,
and marketplace index remain unobserved. Local CI and fresh-install fixtures
must pass before a tag, GitHub release, or marketplace update is created.
Publication requires separate, explicit release authorization and evidence.

## Correction -- 2026-10-03 (append-only; everything above left as published history)

The "Spend modes" section above states that a config predating the
`billing_mode` key defaults to `metered`. That was v0.9.6 behavior. On this tree
the missing-key default is per-harness, and the statement above is superseded for
current trees (the v0.9.6 text itself is preserved, and the published GitHub
release body is that same text):

- Resolution order: an explicit `billing_mode` always wins. When the key is
  **absent**, `budget-check.sh` resolves a per-harness default -- `opencode` and
  `hermes` resolve `free`; `codex` and `claude-code` (`claude` is accepted as an
  alias) resolve `flat`; no harness signal, or an unrecognized one, resolves
  `metered`, fail-closed. The harness comes from `--harness`, then
  `$SEFI_HARNESS`, then the machine-local `.sefi/harness` marker written by
  `/sefi:init`.
- `metered` is opt-in: `billing_mode: metered`, explicitly.
- A `billing_mode` key that is **present with no value** is a usage error in both
  `budget-check.sh` (exit 2) and `validate-budget.sh`, not a request for the
  default.
- Measured behavior on a keyless config, `budget-check.sh --harness <name> --scope
  daily --spent 999.00` against the 2.00 daily cap: `opencode` and `hermes` exit 0
  with a recorded `billing_mode=free` skip; `codex` and `claude-code` exit 0 with a
  recorded `billing_mode=flat` skip; no harness signal exits 1 (EXCEEDED, enforced).

Fixture coverage in `test-scripts.sh` pins all of the above, per harness, plus the
empty-value and argument-parsing cases. See `docs/BUDGET.md` for the authoritative
spend-mode table.
