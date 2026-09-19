---
description: Produce a bounded, evidence-backed local codebase map, trace, impact report, delta, or visualization.
managed-by: sefi-agents
---

# /sefi:map-codebase

Route this command to `codebase-cartographer`. It has read-only access to source code and
may write only `state/codebase-map-<slug>.md`, its matching JSON file, and an optional
render receipt or artifact.

Usage: `/sefi:map-codebase <MAP|TRACE|IMPACT|DELTA|VISUALIZE> [target]`.

Start with deterministic local evidence: Git, `rg`, file paths, line ranges, and content
hashes. Each map node carries a type, source evidence, confidence, and freshness status
(`pending`, `stale`, or `ready`). Relationships must use only `contains`, `imports`,
`calls`, `reads`, `writes`, `emits`, `subscribes`, `depends_on`, or `routes_to`.

Keep the result bounded to the named target and likely affected tests. Render only when the
user requests a visual or the map has at least four nodes and three non-containment edges.
Use an installed graph tool only when it provides fresh evidence; otherwise use Git and
`rg`, with validated Mermaid as the portable fallback. State any uncertainty rather than
inventing an edge.
