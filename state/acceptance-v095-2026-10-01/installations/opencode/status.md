# Step 4 status: OpenCode (installation engineer assessment; QA judges)

Source record: `../sources/sources.log`. Per-run bindings:
`released/source.txt` (`2fe3bb3…`), `candidate/source.txt` (`6e9f432…`).

| Leg | Verdict | Evidence |
|---|---|---|
| `opencode` CLI presence | PENDING | Absent on host and container (`../env/s4-00-env.log:11`); installing it is unauthorized |
| Install from released source (`OPENCODE_HOME` isolated) | PASS | `released/install.exit` exit 0 (spot-checked; full detail captured on candidate leg) |
| Install from candidate source (`OPENCODE_HOME` isolated) | PASS | `candidate/install.exit` exit 0; `candidate/install.log:1-17` 17 agents transformed, `:18-37` 20 skills incl `systems-audit`, `:38-50` commands incl `audit.md`, `:51-90` scripts + `wrote package manifest`, `:91-95` success + `/sefi:init` instruction |
| Real discovery (agents/skills/commands/scripts) | PASS | `candidate/content.log:6-26`: 17 agents incl `systems-auditor.md`, `skills/systems-audit`, `commands/audit.md`, `scripts/ci/validate-audit-report.sh` |
| Mode / permission / model transforms | PASS | No raw `tools:` lines, `permission:` present (`:27-31`); `sefi-agents mode: primary`, `systems-auditor mode: subagent` (`:32-34`); no `model:` line = shipped `flexible` (`:35-36`) |
| Installed runtime references (placeholder resolved) | PASS | No raw `${CLAUDE_PLUGIN_ROOT}` in installed skill (`:50-52`); manifest `sefi-package-manifest/v1` with per-file hashes (`:37-49`) |
| Manifest `source_version`/`source_commit` fields | UNKNOWN | Manifest head captured only through `managed_files`; the two source fields were not captured before the ephemeral install root was discarded (cause, not a source gap: revision pinned by procedure in `source.txt`) |
| Installed managed-file hashes | PASS | `candidate/content.log:53-55` (SKILL `b6936a26…`, validator `b3c48d97…`, matching Claude legs) |
| `/sefi:audit build`, `/sefi:init` on synthetic projects | PENDING | No `opencode` CLI and no model credentials; adding either is unauthorized |
| Installed validator, explicit root (candidate runtime) | PASS | `validator/legs.log`: usage exit 2; malformed exit 1 (9 errors); S22 raw candidate report exit 0. No-report run observed exit 0 vacuous (`OK (0 report(s) checked)`), recorded as observed |
| Supported flags (no invention) | RECORDED | `[--force] [--model-map <path>] [--auto-update]` (`../env/help-sources.log:20`); `OPENCODE_HOME` override honored (install-opencode.sh:116); no pinning flags: limitation recorded |

Real user config untouched: all runs used disposable `OPENCODE_HOME`; see `INCIDENT.md` for the one accidental no-force run against the real home (refused, zero writes).

## Native legs, 2026-10-02 (installation engineer assessment; QA judges)

CLI: `opencode` 1.18.34 installed 2026-10-02 into a disposable npm prefix
(`../env/s4n-01-cli-install-20261002.log:13-20`). All runs with disposable
`HOME`+`USERPROFILE`+`OPENCODE_HOME`; real `HOME/.config/opencode` has no
2026-10-02 touches (`native-20261002/forensics-20261002.log` tail section).
Budget basis: see Claude status note (measured $5.84 EXCEEDED both caps;
one-time human override only).

| Leg | Verdict | Evidence |
|---|---|---|
| `opencode` CLI presence / version | PASS | `native-20261002/s4n-12-opencode.log:5` `1.18.34`, exit 0 |
| Install from candidate HEAD `25c4b97` (`OPENCODE_HOME` isolated) | PENDING (BLOCKED-as-evidence) | Content fully laid down and transforms verified (below), but installer exit 1: `package-manifest: Python is required` (`s4n-12-opencode.log:8,16`); manifest unwritten; host git-bash has no Python and adding one needs separate authorization |
| Real discovery (agents/skills/commands/scripts) | PASS (bytes) | 17 agents incl `systems-auditor.md`, 20 skills incl `systems-audit`, commands incl `audit.md`, `scripts/ci` present (`s4n-12-opencode.log:19-60`) |
| Mode / permission / model transforms | PASS (bytes) | No raw `tools:` lines; `sefi-agents mode: primary`, `systems-auditor mode: subagent`; no `model:` line = shipped `flexible`; no unresolved placeholder (`s4n-12-opencode.log:62-78`) |
| Installed managed-file hashes | RECORDED | SKILL `b6936a26…` (= Step-4 container value: installer normalizes worktree CRLF to LF, verified by byte dump), validator `0b817a4b…` (`s4n-12-opencode.log:91-92`) |
| `/sefi:audit build` | PENDING | `opencode run` did not fail fast on auth: it began local read-only exploration and was killed by the 120s bound (exit 124, no report written, `s4n-12-opencode.log:94` + `oc-run.out`); only observed backend is the ambient outer-harness server (env carries its credentials), not an isolated opencode identity, so this is not a valid invocation leg; no isolated model credentials exist. Not repeated; see `../INCIDENT-native-20261002.md` |
