---
description: Run one discovery turn and write findings to state/triage.md without implementing.
---

# /sefi:triage

Run a single discovery turn. Read failed CI, recent issues, commits since the last run, and
any prior `state/triage.md`; judge each finding's actionability. Write findings to
`state/triage.md` (one row per finding plus a resume block). Do NOT implement anything.
Uncertain items go to `inbox/`. This is discovery only; handoff and verification are the
loop's job.
