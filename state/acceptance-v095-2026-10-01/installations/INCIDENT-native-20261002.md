# Incident notes: native-leg completion, 2026-10-02 (Step 4 item 1)

Supplements (does not amend) `INCIDENT.md`. No commit, push, merge, version,
tag, or release change was made at any point.

## 1. `codex exec` wrote runtime state into the real HOME despite `CODEX_HOME`

- What ran: `CODEX_HOME=<disposable> codex exec --skip-git-repo-check "Use
  $systems-audit for the build scope"` (stdin closed, 120s bound),
  2026-10-02 ~13:00 UTC, plus one earlier `exec` without the flag and one
  `codex doctor`, all with `CODEX_HOME` set to the disposable dir.
- Observed effect: real `HOME/.codex/.codex-global-state.json` and `.bak`
  carry mtimes inside the probe windows (evidence:
  `codex/native-20261002/s4n-11d-codex-impact.log:6`);
  `logs_2.sqlite`/`models_cache.json` also touched. `CODEX_HOME` isolation
  is therefore NOT complete for `codex exec`: the CLI maintains global
  state in the default home regardless.
- NOT affected: real `AGENTS.md` (2026-09-11), `config.toml` (2026-10-01),
  `auth.json` (2026-10-01) -- all predate this session and are unmodified;
  `auth.json` was never opened. The candidate installer itself never ran
  successfully, so no sefi content reached the real home.
- Confounder: other same-day touches exist OUTSIDE these probe windows
  (concurrent SYSTEM writers are active on this host), so per-file
  attribution beyond the in-window mtimes is UNKNOWN.
- Remediation: no further `codex exec`/`doctor` runs this item (the 401
  cause is already recorded). The state JSONs were left as-is: rewriting
  them would be a further destructive-adjacent action with no correct
  content available.

## 2. `opencode run` did not fail fast; killed by timeout bound

- What ran: `opencode run "Run /sefi:audit for the build scope."` with
  disposable `HOME`+`USERPROFILE`+`OPENCODE_HOME`, stdin closed, 120s
  bound, in an empty synthetic project dir.
- Observed: exit 124 (timeout kill). Before the kill it executed local
  read-only PowerShell exploration (`Get-ChildItem`, `Test-Path`) of the
  stage directory and wrote no audit report (evidence:
  `opencode/native-20261002/s4n-12-opencode.log:94`,
  `opencode/native-20261002/oc-run.out`,
  `opencode/native-20261002/forensics-20261002.log`).
- Likely backend (NOT verified): the ambient outer-harness opencode server
  (this shell inherits its server credentials via env); no isolated model
  credentials exist. This run is therefore not a valid invocation leg and
  was not repeated.
- Real `HOME/.config/opencode` shows no 2026-10-02 touches.

## 3. Budget: measured EXCEEDED, override is the sole basis

- `budget-check.sh` initially exit 3 (CANNOT MEASURE: no ccusage, no jq on
  host git-bash). Installed ccusage 20.0.26 into the disposable prefix and
  measured via `ccusage daily --json --offline` + node math (no jq/python
  on host): today spend $5.842749650000001 (this session's opencode
  ledger).
- Both gates EXCEED with the measured figure: dispatch cap $0.15 and daily
  cap $2.00, exit 1 (evidence:
  `env/s4n-05-budget-gates-20261002.log:3-7`,
  `env/ccusage-daily-20261002.json`).
- Execution continued solely under the human one-time spend override for
  this item recorded in the dispatch. No subagent was dispatched; shell/CLI
  probes made zero model calls (version/help/auth-failure paths only),
  except the opencode run in note 2 above, which is disclosed there.

## 4. Tooling side notes (no impact)

- `s4n-04` first measured-spend attempt recorded `JSON-PARSE-FAIL`: the
  Windows node binary does not resolve git-bash `/c/...` paths (resolved
  to `D:\c\...`). Re-ran with a `C:/...` path (`s4n-05`); the trail is
  preserved, not edited.
- `s4n-11c` hit the 300s tool timeout on an unbounded `find` over the
  live real `~/.codex` (concurrent writers) combined with a hanging
  container TCP probe; superseded by bounded `s4n-11d`. No repeats needed.
- `s4n-10d` logged one `fatal: detected dubious ownership` line: with
  `HOME` overridden, git lost the real-HOME `safe.directory` exception.
  Cosmetic only; the rev was re-captured before the override (`s4n-10e`).
