---
description: Print open findings, pending human reviews, and budget headroom (read-only).
---

# /sefi:status

Read-only. Report:
- Open findings and resume blocks from `state/*.md`, with cycle counters.
- Per-target PASS/REJECT rates from `state/metrics.md`.
- Pending human reviews in `inbox/`.
- Budget headroom from `config/budget.yml`.

If `ccusage` is on PATH, show real spend (per-adapter via `--by-agent`) alongside the caps;
otherwise show the caller-tracked figure. Never write anything.
