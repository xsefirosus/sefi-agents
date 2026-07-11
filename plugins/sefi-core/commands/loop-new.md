---
description: Interview briefly, then generate a new loops/<name>.loop.md with all six elements filled.
---

# /sefi:loop-new

Interview the user briefly for the loop's purpose, trigger, and checkpoint. Then generate
`loops/<name>.loop.md` from the template in `docs/LOOPS.md`, filling all six elements
(Trigger/Scheduling, Discovery, Handoff, Verification, Persistence, Human checkpoint) plus
the Budget block. Refuse to write the file if any element is blank; ask for the missing one
instead. Confirm the five moves are all present before saving.
