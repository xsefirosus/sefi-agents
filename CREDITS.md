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
- [taste-skill](https://github.com/Leonxlnx/taste-skill) - the Design System Map
  reference (MIT; condensed to this repository's format).
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
- [codegraph](https://github.com/colbymchenry/codegraph)
- [cognee](https://github.com/topoteretes/cognee)
- [graphify](https://github.com/Graphify-Labs/graphify)
- [mem0](https://github.com/mem0ai/mem0)
- [obsidian-skills](https://github.com/kepano/obsidian-skills)

### v0.8.0 research inputs

The following repositories were reviewed file by file at the named commits. They informed
independently written behavior contracts only; Sefi does not copy their source, prompts,
schemas, assets, or tool definitions.

- [emilkowalski/skills](https://github.com/emilkowalski/skills) at
  `85e8e2363b713506e1d5b6e07a0eb2da66be1bc3` (MIT).
- [MengTo/threeui](https://github.com/MengTo/threeui) at
  `68802d5428071ada5c20db8094b1649e6bb770ed` (MIT).
- [tt-a1i/archify](https://github.com/tt-a1i/archify) at
  `72c750bb070d95171dbb2244e5b62b1b7da69c12` (MIT).
- [trailhq/Graft](https://github.com/trailhq/Graft) at
  `8c05769618d413041ea2c8891f82d566f0461b3c` (MIT).
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
