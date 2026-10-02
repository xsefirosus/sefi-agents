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

## Native legs, 2026-10-02 (installation engineer assessment; QA judges)

No `hermes` CLI was installed: no channel is documented in
Install.md/adapters/HERMES.md; `npm search hermes` 2026-10-02 surfaces only
unrelated packages; winget is absent from this shell; no package ID is known
(`../env/s4n-02-hermes-probe-20261002.log`). Discovery of a trustworthy
non-interactive channel needs a human pointer; guessing a package name or
URL would be invention. Budget basis: see Claude status note (measured $5.84
EXCEEDED both caps; one-time human override only).

| Leg | Verdict | Evidence |
|---|---|---|
| `hermes` CLI presence / version | PENDING | Still ABSENT (`native-20261002/attempt-20261002.log:5`); installing it is not possible from any verified non-interactive channel |
| `install-hermes.sh` attempt at candidate HEAD `25c4b97` | PENDING (BLOCKED-as-evidence) | `hermes CLI not found on PATH`, exit 1 before any write (`attempt-20261002.log:7-8`, `hm-attempt.out`); nothing written anywhere by this leg |
| Native skills discovery, canonical `sefi-core` beside config, source/hash manifest, runtime + project roots | PENDING | All require the `hermes` CLI; no fake CLI or local fixture substituted |
| `Run the systems-audit skill for the build scope` | PENDING | Requires Hermes runtime + model credentials; adding either is unauthorized |
| Pinning support | LIMITATION RECORDED (unchanged) | Unchanged from Step 4: no source-selection flag; native path fetches default-branch bytes |
