# Adapter contract

Sefi's agent source is harness-neutral. Every agent names a `tier` (`high`, `mid`, or
`low`) rather than a provider model. A harness adapter supplies the runtime-specific
install, permission, hook, delegation, model, and verification details.

## Shipped adapters

| Harness | Manifest | Model strategy | Installer |
|---|---|---|---|
| Claude Code | `manifests/claude-code.yml` | mapped, with a guarded orchestration fallback | plugin install or `install.sh --target claude` |
| Codex | `manifests/codex.yml` | mapped custom-agent profiles | `install-codex.sh` or `install.sh --target codex` |
| OpenCode | `manifests/opencode.yml` | flexible by default; optional explicit map | `install-opencode.sh` or `install.sh --target opencode` |
| Hermes | `manifests/hermes.yml` | flexible global model | `install.sh --target hermes` |

`bash install.sh --target <adapter-id>` loads the corresponding manifest and refuses an
unknown or incomplete contract. `--model-map path/to/model-map.yml` replaces the shipped
map for a mapped adapter or supplies explicit OpenCode mappings.

## Project onboarding

Installation is user-wide, but `/sefi:init` is project-scoped. After a successful install,
run `/sefi:init` once from each project root before its first routed request. An installer
must never auto-initialize a repository because it cannot safely identify the intended root
or change that project's files.

`/sefi:init` keeps runtime `memory/` local and ignored, while the packaged
`templates/memory/` source remains shipped for later project initialization. Its optional
cross-project memory mirror is local and private to the current OS user, off by default,
and enabled only after an interactive yes; unattended initialization leaves it off.

The reminder is intentionally installer output, not a fabricated hook. The documented
Claude Code and Codex hook is session start, and OpenCode's documented event is
`session.created`; none reports a first routed request. Hermes has no confirmed hook event.
Those events may provide session-start context, but must not be described as a one-time
first-routed-request callback.

Every shipped harness receives the same canonical Cartographer and Technical Writer bodies.
`/sefi:map-codebase` uses local Git and `rg` evidence by default; optional Graft or CodeGraph
enrichment is named-only and never installed or configured by Sefi. Substantial current-state
documentation uses local Claim sidecars and existing task receipts. These features add no
provider call, hosted service, or adapter-specific dependency.

Copied fallback installs write a package manifest only for their byte-for-byte `scripts/`
subtree. Check it with the installed `package-manifest.sh` using the install destination as
both `--root` and the parent of `--destination`. Generated agents and prose whose plugin-root
placeholder is rewritten have no source-byte manifest; native Codex and Hermes installs do
not create a copied package tree to check.

## Private or new adapters

Use `bash install.sh --adapter path/to/adapter.yml` for a complete local manifest whose
`support` value is `custom`. This makes no claim that the harness is shipped or verified.
To promote it, add its manifest to `adapters/manifests/`, document the runtime wiring, and
add passing adapter validation coverage.

Never put a provider API key in a manifest or model map. Configure credentials in the
selected harness or its CI secret store.
