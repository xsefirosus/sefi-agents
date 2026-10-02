# Step 4 status: Codex (installation engineer assessment; QA judges)

Source record: `../sources/sources.log`. Per-run binding: `source.txt`
(candidate `6e9f432…`, tree `2353aa02`).

| Leg | Verdict | Evidence |
|---|---|---|
| `codex` CLI presence / version | PENDING | Absent on host and container (`../env/s4-00-env.log:10`); installing it is unauthorized |
| `--candidate-marketplace` without `CODEX_HOME` | PASS (gate) | `gates.log:3-5`: exact message `--candidate-marketplace requires an explicit isolated CODEX_HOME`, exit 2, no writes |
| Candidate install with isolated `CODEX_HOME` | BLOCKED-as-evidence (native leg PENDING) | `candidate-attempt.log:1-3`: `Codex CLI not found on PATH`, exit 1; isolated home stayed empty (`:4-7`); real `HOME/.codex` untouched (`:8-10`) |
| Isolation is command-local, global home never repurposed | PASS | `CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"` (`candidate-attempt.log:12`, install-codex.sh:472); every run exported a disposable `CODEX_HOME` |
| New-session `$systems-audit` discovery, auditor profile survival, actual `Use $systems-audit for the build scope` | PENDING | Requires `codex` CLI + session; no fake CLI or fixture substituted |
| Supported flags (no invention) | RECORDED | `install-codex.sh [--model-map <path>] [--candidate-marketplace <repo-root>]` (`../env/help-sources.log:18`); no `--revision`/`--pin` exists: unsupported pinning remains a limitation as the plan states |

## Native legs, 2026-10-02 (installation engineer assessment; QA judges)

CLI: `codex` 0.160.0 installed 2026-10-02 into a disposable npm prefix
(`../env/s4n-01-cli-install-20261002.log:13-20`). Candidate source is branch
head `25c4b97` (`../sources/native-sources-20261002.log`).
Budget basis: see Claude status note (measured $5.84 EXCEEDED both caps;
one-time human override only).

| Leg | Verdict | Evidence |
|---|---|---|
| `codex` CLI presence / version | PASS | `native-20261002/s4n-11-codex.log:5` `codex-cli 0.160.0`, exit 0 |
| `--candidate-marketplace` without `CODEX_HOME` | PASS (gate) | Re-verified exit 2, exact message (`s4n-11-codex.log:9`) |
| Candidate install with isolated `CODEX_HOME` | PENDING (BLOCKED-as-evidence) | New exact cause (CLI now present): `Python is required to verify the installed plugin source and write TOML profiles` (`s4n-11-codex.log:12`), exit 2; isolated home stayed empty; host git-bash has no Python and adding one needs separate authorization |
| New-session `$systems-audit` discovery / auditor profile / actual invocation | PENDING | Install never completed; `codex exec` with the tool-suggested `--skip-git-repo-check` reaches the API and fails `HTTP 401 Unauthorized` from `wss://api.openai.com/v1/responses` (`s4n-11b-codex.log:36-40`), exit 1; no credentials exist and adding them is unauthorized (`codex doctor`: `no Codex credentials were found`, `s4n-11-codex.log:24`) |
| Real-home containment | VIOLATION RECORDED, contained | `codex exec` with `CODEX_HOME` set still rewrote real `HOME/.codex/.codex-global-state.json`+`.bak` (mtimes inside probe windows); settings/credentials (`AGENTS.md` Sep-11, `config.toml`/`auth.json` Oct-01) NOT modified, `auth.json` never opened (`s4n-11d-codex-impact.log:6,17-19`); concurrent SYSTEM writers also active (cause of other touches UNKNOWN). No further `codex exec`/`doctor` runs; see `../INCIDENT-native-20261002.md` |
