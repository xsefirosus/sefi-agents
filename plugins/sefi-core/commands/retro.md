---
description: Run the retro-improve self-improvement pass once, honoring sefi.config.yml.
---

# /sefi:retro

Run the retro-improve skill once. Read `state/metrics.md` (worst success rate first),
evaluator REJECTs, gate failures, and librarian `## Possible contradiction` flags. Honor
`sefi.config.yml`: if `improvement.enabled` is false, write the proposed diff to
`state/retro-<date>.md` and stop. Obey every retro-improve HARD GUARD: managed-by files
only; bounded change; single keyspace; edit what the runtime loads.
