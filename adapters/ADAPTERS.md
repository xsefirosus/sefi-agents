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

## Private or new adapters

Use `bash install.sh --adapter path/to/adapter.yml` for a complete local manifest whose
`support` value is `custom`. This makes no claim that the harness is shipped or verified.
To promote it, add its manifest to `adapters/manifests/`, document the runtime wiring, and
add passing adapter validation coverage.

Never put a provider API key in a manifest or model map. Configure credentials in the
selected harness or its CI secret store.
