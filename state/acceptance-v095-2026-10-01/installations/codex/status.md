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
