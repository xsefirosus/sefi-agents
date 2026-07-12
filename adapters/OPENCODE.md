# Running sefi-agents on OpenCode

Thin adapter. Canonical bodies live under `plugins/sefi-core/`; the action, tool, and
hook-event maps live in `skills/sefi-orchestration/references/harness-actions.md`. This
file only names the OpenCode-specific wiring.

## 1. Connect OpenCode Zen

Point OpenCode at the Zen provider and select a model:
- Base URL: `https://opencode.ai/zen/v1`
- Model: `deepseek-v4-flash-free` (free window) or `deepseek-v4-flash` (paid fallback)

## 2. Install

OpenCode auto-discovers agents, skills, and commands under
`~/.config/opencode/{agents,skills,commands}/` (or `$OPENCODE_HOME` if set). From the
repo root:

```sh
bash plugins/sefi-core/scripts/install-opencode.sh
# or, through the human-fallback installer:
./install.sh --target opencode
```

`--force` re-installs over an existing copy. Skills and commands are copied verbatim;
their frontmatter has no field collisions with OpenCode's schema. Agents are
transformed: OpenCode's `tools` field is a strictly-typed `{name: boolean}` object (and
deprecated in favor of `permission`), so a raw copy of our `tools: Read, Grep, ...`
string fails schema validation. The script converts each agent's `tools:` /
`disallowedTools:` pair into the 15-key `permission:` mapping OpenCode expects
(conversion table lives in the script's comments). Every other frontmatter field and the
entire body is preserved byte-for-byte.

## 3. Headless (CI loops)

Invoke non-interactively with `opencode run`, piping the prompt via stdin.

## 4. Hook-event map

The SessionStart memory injection maps to OpenCode's `session.created`; a PreToolUse gate
maps to `tool.execute.before`; a Stop hook maps to `session.idle`. Full table:
`skills/sefi-orchestration/references/harness-actions.md`.

## Troubleshooting

OpenCode does not have a single all-in-one `doctor` command (the way Hermes has
`hermes doctor --fix` or Codex has `codex doctor`). For general config/paths diagnostics
use:

- `opencode debug paths` -- shows the real config / data / cache directories on the
  current machine.
- `opencode debug config` -- shows the fully resolved, merged config.

For an agent that fails to load with `Configuration is invalid`, `opencode debug agent
<name>` shows the parse error. If the error points at a `tools: <string>` field, the
installed copy under `~/.config/opencode/agents/` still has the raw string -- re-run
`install-opencode.sh --force` to regenerate it.
