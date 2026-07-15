# OPTIONAL TOOLS

External tiers a user MAY add. None is vendored into the plugin; each is shelled-out-to or
pointed-at, so the zero-runtime-dependency install stays intact. Each entry ends with a
"consider it only if" line.

## Code-structure connectors (one-command, opt-in)
These index *code structure* -- orthogonal to the memory vault, so there is no double-write.

### codegraph
A local typed code-graph over `node:sqlite` (a Node built-in), 9 npm deps, no native
compile, no API keys, self-managing daemon (`CODEGRAPH_NO_DAEMON=1` to disable). Hermes is a
first-class installer target. One command:
```sh
codegraph install && codegraph init
```
Report its defensible metric: ~58% fewer tool calls, with file reads dropping to roughly
zero across repo sizes; treat any token-percentage as noisy and scale-dependent.
- Consider it only if: your loops spend most of their tool calls navigating a large codebase.

### graphify
A pure code-graph skill (markdown + CLI, no daemon or DB by default; optional MCP behind a
`[mcp]` extra). Hermes is a wired target. Note: it installs as a **Python** tool
(`uv tool install graphifyy` or `pipx`) -- fine as an optional external choice, but not
zero-Python like codegraph.
- Worktree caveat: before running graphify inside `.worktrees/*`, set
  `GRAPHIFY_OUT=<shared absolute path>` or every worktree pays full re-extraction (graphify's
  own issues #686 / #1423 -- independent evidence for the project-local worktree decision).
- Consider it only if: you want a code graph without a running daemon and Python is acceptable.

### codebase-memory-mcp
A local single-binary typed code property graph served over **MCP** (an openCypher read
subset), zero-config, no embedded LLM. Corrected numbers: ~10x fewer tokens and 2.1x fewer
tool calls across 31 repos at 83% answer quality (the "120x / 99%" headline is a narrow
5-query best case). The MCP-native alternative beside codegraph.
- Consider it only if: you prefer an MCP server over a CLI daemon.

## Real-spend accounting
### ccusage
Reads each agent CLI's own local ledger (Claude JSONL, Hermes `state.db`, OpenCode
`opencode.db`, Codex) and reports real cost. `budget-check.sh` and `/sefi:status` use it
automatically when present (`--offline`, no network mid-loop; `--by-agent` for per-adapter
spend).
- Consider it only if: you want real spend instead of the caller-tracked figure. Optional,
  never required.

## Persistent-memory upgrades
The markdown vault is the default. Heavier backends run a background service or pull a heavy
dependency tree.

### cognee
Pip-installable knowledge-graph memory library (LLM-extracted entities/relationships over
embedded SQLite+LanceDB+Ladybug by default, Postgres/Neo4j optional) with its own Claude
Code plugin. Per-document extraction requires LLM API calls, adding token cost on every
memory write.
- Consider it only if: the project needs LLM-grounded graph reasoning over ingested
  documents and accepts a substantial Python dependency chain plus per-write LLM
  extraction cost.

### agentmemory, MemOS, mem0
Not yet individually profiled here -- UNKNOWN architecture/cost details for this repo's
purposes; do not assume a specific footprint until confirmed against each project's own
docs.
- Consider any only if: the vault is genuinely outgrown and a persistent service is
  acceptable. Do not cite "SQLite / no external DB" as "lightweight" -- it still adds a
  service to run.

## Context / output compression
- **Headroom** -- multi-mode context compression; expect ~15-20% for real coding sessions,
  not the 60-95% JSON-only headline.
- **RTK** -- a shell-output rewriter.
- Document, do not vendor: rewriting cached tool-result bytes on the fly can break a
  provider's prompt-cache hits.
- Consider either only if: you have measured a specific compression need, not speculatively.
