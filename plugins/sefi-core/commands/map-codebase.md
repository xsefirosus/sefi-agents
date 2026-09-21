---
description: Produce a bounded, evidence-backed local codebase map, trace, impact report, delta, visualization, or context packet.
managed-by: sefi-agents
---

# /sefi:map-codebase

Route this command to `codebase-cartographer`. It has read-only access to source code and may
write only `state/codebase-map-<slug>.md`, its matching JSON file, and declared local
`.sefi/cartographer/<slug>/` derivatives.

Usage:

```text
/sefi:map-codebase <MAP|TRACE|IMPACT|DELTA|VISUALIZE|CONTEXT> [target]
/sefi:map-codebase DELTA [target] [--base <git-ref>]
/sefi:map-codebase CONTEXT [target] [--budget <estimated-tokens>]
```

The validated artifact is `sefi-codebase-map/v2`. Authoritative maps are
`state/codebase-map-<slug>.md` and `state/codebase-map-<slug>.json`. `--base` is required when
DELTA has no prior baseline. CONTEXT uses this default and permits an estimated-token override
between 4,000 and 64,000:

```yaml
cartographer:
  context_packet_budget: 24000
  max_context_packets: 8
```

Read `cartographer.context_packet_budget` and `cartographer.max_context_packets` from the
initialized project configuration before generating packets. A command-line `--budget`
override stays within 4,000 and 64,000; never produce more than the configured packet count.

Start with deterministic local Git and `rg` evidence. Validate worktree identity and baseline
before reuse; record content and structural hashes, file classification, freshness, source
evidence, unresolved relationships, dynamic boundaries, and likely affected tests. Use only
`contains`, `imports`, `calls`, `reads`, `writes`, `emits`, `subscribes`, `depends_on`, or
`routes_to` for verified relationships. The command never treats heuristics as verified edges.

Keep the result bounded to the named target and likely affected tests. Run the symbol-loss and
secret-filtering gates before publication. IMPACT predicts possible effects before a change;
DELTA reports actual effects after it. CONTEXT creates budgeted local packets. VISUALIZE creates
only an offline local viewer or Mermaid fallback. Use Graft or CodeGraph only when explicitly
named and validated; never install, initialize, or configure either tool. State uncertainty
rather than inventing an edge.
