# Step 4 status: Hermes (installation engineer assessment; QA judges)

Source record: `../sources/sources.log`. Run binding: `source.txt`
(candidate `6e9f432…`, tree `2353aa02`, archive `1214dad8…`).

| Leg | Verdict | Evidence |
|---|---|---|
| `hermes` CLI presence / version | PENDING | Absent on host and container (`../env/s4-00-env.log:12`); installing it is unauthorized |
| `install-hermes.sh` attempt | BLOCKED-as-evidence (native legs PENDING) | `attempt.log:3-5`: `install-hermes.sh: hermes CLI not found on PATH`, exit 1. Hard requirement at install-hermes.sh:84 (`attempt.log:6-8`); config path via `hermes config path` (script :98) unreachable without the CLI |
| Native skills discovery, canonical `sefi-core` beside config, source/hash manifest, runtime + project roots | PENDING | All require the `hermes` CLI; no fake CLI or local fixture substituted as native proof |
| `Run the systems-audit skill for the build scope` | PENDING | Requires Hermes runtime + model credentials; adding either is unauthorized |
| Canonical source content present in candidate tree | RECORDED (not installed) | `attempt.log:9-12`: `skills/systems-audit`, `scripts/ci/validate-audit-report.sh`, `.codex-plugin/plugin.json` exist in the candidate source |
| Pinning support | LIMITATION RECORDED | `install-hermes.sh [--auto-update]` only (`../env/help-sources.log:22`); no source-selection flag exists, and the native path fetches default-branch bytes, so a published native run cannot be presented as candidate proof (per plan: unsupported pinning remains a limitation) |
| Unrelated-file preservation / revision confirmation on install | PENDING | No install executed; nothing was written anywhere by this leg |
