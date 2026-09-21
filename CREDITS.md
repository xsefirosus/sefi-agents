# Credits

Sefi-agents is an independent, zero-runtime implementation. It was shaped by open-source
projects whose ideas, patterns, and lessons helped form its orchestration, memory,
verification, and cost-control design. This is an acknowledgement, not a claim that this
repository vendors or is affiliated with any project below. Each source retains its own
license and terms.

## Direct adaptations and named sources

- [loop-engineering](https://github.com/cobusgreyling/loop-engineering) - loop intake,
  verification, and resume patterns.
- [astral-orchestrator](https://github.com/Demonbane18/astral-orchestrator) - release
  tracking and Codex route-checking approach (MIT).
- [i-have-adhd](https://github.com/ayghri/i-have-adhd) - the config-gated Focus skill
  (MIT; condensed and reworded).
- [Taste Skill](https://github.com/Leonxlnx/taste-skill) at
  `e79ca9ec7e071eb3a3b623c4fb752e853fc3ed58` - direction and design-system mapping
  research (MIT; independently rewritten for this repository).
- [hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution)
  - the bounded self-improvement safety direction used by `retro-improve`.

## Research influences

The projects below were reviewed as research inputs.

### Agent orchestration and delivery

- [superpowers](https://github.com/obra/superpowers)
- [ECC](https://github.com/affaan-m/ECC)
- [agency-agents](https://github.com/msitarzewski/agency-agents)
- [agent-skills](https://github.com/addyosmani/agent-skills)
- [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
- [mattpocock-skills](https://github.com/mattpocock/skills)
- [claude-skills](https://github.com/alirezarezvani/claude-skills)
- [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT)
- [MetaGPT](https://github.com/FoundationAgents/MetaGPT)
- [crewAI](https://github.com/crewAIInc/crewAI)
- [deer-flow](https://github.com/bytedance/deer-flow)
- [gstack](https://github.com/garrytan/gstack)
- [vibecode-pro-max-kit](https://github.com/withkynam/vibecode-pro-max-kit)

### Persistent memory and knowledge

- [MemOS](https://github.com/MemTensor/MemOS)
- [agentmemory](https://github.com/rohitg00/agentmemory)
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
- [CodeGraph](https://github.com/colbymchenry/codegraph) at
  `ba3c21e50d9129d2f5f3843ec3728868ae6d47a1` - v0.9.1 research into per-file freshness,
  unresolved-reference recovery, dynamic boundaries, worktree checks, and relationship
  provenance (MIT; independently rewritten).
- [cognee](https://github.com/topoteretes/cognee)
- [Graphify](https://github.com/Graphify-Labs/graphify) at
  `20a20d30d8e7eef77675651f0199d87f913bd3e7` - v0.9.1 research into graph evidence and
  offline visual exploration (Apache-2.0; independently rewritten).
- [Repomix](https://github.com/yamadashy/repomix) at
  `9f01703a750ec5bfb808a00a93ac2e81ed67df6e` - v0.9.1 research into bounded,
  reproducible repository context packets (MIT; independently rewritten).
- [mem0](https://github.com/mem0ai/mem0)
- [obsidian-skills](https://github.com/kepano/obsidian-skills)

### v0.9.0 design research inputs

The following repositories were reviewed as source inputs at the named revisions. They
informed independently written behavior contracts only; Sefi does not vendor their prompts, datasets, components, or assets.

- [Emil Kowalski Skills](https://github.com/emilkowalski/skills) at
  `85e8e2363b713506e1d5b6e07a0eb2da66be1bc3` - interaction and motion review behavior
  (MIT).
- [ThreeUI](https://github.com/MengTo/threeui) at
  `68802d5428071ada5c20db8094b1649e6bb770ed` - criteria for optional 3D or shader-led
  recommendations (MIT).
- [Impeccable](https://github.com/pbakaus/impeccable) at
  `f2c7051853848826aac2f4646581d62a732155ad` - independently written visual-study and
  interface-quality review boundaries (Apache-2.0).
- [Hallmark](https://github.com/Nutlope/hallmark) at
  `13ac0ec7e148655948100b6396439e481361d690` - independently written direction-first
  interface review behavior (MIT).
- [React Bits](https://github.com/DavidHDev/react-bits) at
  `23b6d2c0ab10b949c7891b3e76b2f801dff186a3` - criteria for optional React effect
  recommendations (MIT with Commons Clause).
- [UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) at
  `de5f12b400775997d213524ef02a7c7d2746806f` - independently written domain-guidance
  scope and provenance constraints (MIT).

### v0.8.0 and v0.9.1 repository-intelligence research inputs

The following repositories were reviewed as source inputs at the named revisions for the
Memory Journalist, Cartographer, and Adoption Scout contracts.

- [tt-a1i/archify](https://github.com/tt-a1i/archify) at
  `72c750bb070d95171dbb2244e5b62b1b7da69c12` - map validation, diagnostics, and offline
  visual delivery research (MIT; independently rewritten).
- [trailhq/Graft](https://github.com/trailhq/Graft) at
  `8c05769618d413041ea2c8891f82d566f0461b3c` - incremental local graph freshness and
  bounded retrieval research (MIT; independently rewritten).
- [Understand Anything](https://github.com/Egonex-AI/Understand-Anything) at
  `6df3065f1d8ddc2ce3615314d1d493f36d6b1c80` - independently written repository-map and
  evidence-review behavior research (MIT).
- [OpenWiki](https://github.com/langchain-ai/openwiki) at
  `715109a8ab1cda6d47680fcc8170e203c751bf61` - independently written versioned
  documentation Claims, staleness preflight, sparse reconciliation, resumable page work,
  page manifests, deterministic finalization, and evolution-fixture research (MIT).
- [x1xhlol/system-prompts-and-models-of-ai-tools](https://github.com/x1xhlol/system-prompts-and-models-of-ai-tools)
  at `1e4203a7d88873c1b37ab2d1c07074fea498c274` (GPL-3.0; behavior research only,
  with no prompt or schema text copied).
- [zhayujie/CowAgent](https://github.com/zhayujie/CowAgent) at
  `8f1b19f1e72db0b46772f78f9c760b04b1836428` (MIT terms).
- [HKUDS/nanobot](https://github.com/HKUDS/nanobot) at
  `a3686d5eba9ec12a7c505788cfb905282769a5dd` (MIT).

### Token discipline

- [ponytail](https://github.com/DietrichGebert/ponytail)
- [rtk](https://github.com/rtk-ai/rtk)
- [caveman](https://github.com/JuliusBrussee/caveman)
- [ccusage](https://github.com/ccusage/ccusage)
- [headroom](https://github.com/headroomlabs-ai/headroom)
- [claude-token-efficient](https://github.com/drona23/claude-token-efficient)

## How to report an omission

If a source is missing or a credit needs correction, please open an issue with the source
URL and the relevant Sefi file or feature. We will correct the record without claiming
credit that cannot be verified.

Sefi does not vendor third-party code, prompts, schemas, parsers, binaries, databases,
agents, dashboards, visualizers, generated wikis, or assets from these sources.
