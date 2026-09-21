# OPTIONAL TOOLS

External tiers a user MAY add. None is vendored into the plugin; each is shelled-out-to or
pointed-at, so the zero-runtime-dependency install stays intact. Each entry ends with a
"consider it only if" line.

## Design libraries

### ThreeUI and React Bits

These are design-task recommendations, never Sefi dependencies. UI/UX Designer first
inspects the target manifest and may recommend at most one external library for a task.
ThreeUI can fit a web project with a central 3D or shader-led experience when performance
and accessibility costs are justified. React Bits can fit a React project when a named
text, background, or interaction effect fits the selected direction and a small native
implementation is not more appropriate.

Record the package and version or `UNKNOWN`, capability, fit, bundle cost, accessibility
and reduced-motion behavior, license status, native alternative, and `Approval: required`.
Do not install a package or copy ThreeUI or React Bits source, assets, shaders, fonts,
examples, or components into Sefi. React Bits is credited under MIT with Commons Clause;
review that license before a project adopts it.

- Consider either only if: the target project and selected direction justify its cost and
  the user approves a concrete recommendation.

## Code-structure connectors (one-command, opt-in)
These index *code structure* -- orthogonal to the memory vault, so there is no double-write.

### Archify and Graft

The Codebase Cartographer works with local Git and `rg` by default. Archify can render a
bounded evidence-backed architecture diagram, and Graft can provide a richer local code
graph when either is already installed. Both are optional: Sefi records source hashes,
freshness, and a rendering receipt, then falls back to validated Mermaid or plain Markdown.
Neither tool is installed, required, or allowed to weaken the local-first privacy boundary.
- Consider either only if: a requested map has enough relationships that a bounded visual is
  easier to review than text.

### codegraph
CodeGraph is an optional local Rust-backed code index with a SQLite store and optional daemon
behavior. Its upstream installation model, parsers, telemetry controls, MCP support, and UI
server are not part of Sefi. Cartographer uses it only when a user explicitly names it for a
targeted trace, impact, delta, context packet, or dynamic-boundary investigation. It checks
that the command responds and that its index belongs to the current worktree, records its
version and provenance, and falls back to Git and `rg` if either check fails. Sefi never
installs or initializes CodeGraph, starts its daemon, changes telemetry, or contacts the
network. Any upstream benchmark number is source-reported and revision-specific, not a Sefi
performance claim.
- Consider it only if: it is already installed locally and a named mapping question needs
  supported symbol enrichment beyond Git and `rg`.

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
