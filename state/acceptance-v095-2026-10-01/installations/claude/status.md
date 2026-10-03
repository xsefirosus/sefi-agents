# Step 4 status: Claude Code (installation engineer assessment; QA judges)

Source record: `../sources/sources.log` + `../sources/host-fetch.log`.
Released `2fe3bb348977a3837a8ef1fb82197afa537d1200` (tree `58fd8163`);
candidate `6e9f432d25de62abca670ee819ea2442d1aab2d0` (tree `2353aa02`).
Per-harness source binding: `released/source.txt`, `candidate/source.txt`.

| Leg | Verdict | Evidence |
|---|---|---|
| Native marketplace path (`/plugin marketplace add`, `/plugin install`) | PENDING | `claude` CLI absent on host and container (`../env/s4-00-env.log:9`); installing it is unauthorized |
| Fallback `install.sh --target claude` from released source | PASS | `released/install.exit` exit 0; `released/content.log:10-15` all five refs PRESENT (skill, auditor, evidence-method, report-contract, validator); settings `CLAUDE_PLUGIN_ROOT` + hooks `PreToolUse,SessionStart` (`:20-22`); managed hashes (`:24-26`, SKILL `b6936a26…`) |
| Fallback `install.sh --target claude` from candidate source | PASS | `candidate/install.exit` exit 0; `candidate/content.log:10-22` same refs PRESENT and wired; SKILL hash identical `b6936a26…`, validator identical `b3c48d97…`, auditor differs (`9a94ea7f…` vs `1ebe9ac8…`) as expected |
| Fresh `/sefi:audit build` (either source install) | PENDING | No `claude` CLI and no model credentials on the acceptance host; adding either is unauthorized |
| Installed validator, explicit root (candidate runtime) | PASS | `validator/legs.log`: usage exit 2 (`:2-5`); malformed report exit 1 with 9 errors (`:9-20`); Step-3 S22 raw candidate report exit 0 (`:33-36`) |
| Validator with no report present | OBSERVED (exit 0) | `validator/legs.log:6-8` prints `OK (0 report(s) checked)` exit 0, not exit 2; recorded as observed for QA (vacuous pass, not runtime proof) |
| `/sefi:init` on isolated synthetic projects | PENDING | Init is harness-issued; no harness available. Synthetic projects were bare dirs; explicit-root legs above still executed |

Real credentials, permissions, services, scanner policy: untouched (all installs used disposable `HOME=/tmp/s4/home-claude-*`; real `HOME/.claude` never referenced).

## Native legs, 2026-10-02 (installation engineer assessment; QA judges)

CLI: `claude` 2.1.287 installed 2026-10-02 into a disposable npm prefix
(`../env/s4n-01-cli-install-20261002.log:13-20`). All runs with disposable
`HOME`+`USERPROFILE`; real `HOME/.claude` newest entry still 2026-09-09
(`codex/native-20261002/s4n-11d-codex-impact.log:21-34`).
Budget basis: measured spend $5.842749650000001 (ccusage, opencode ledger,
`../env/s4n-05-budget-gates-20261002.log:3-7`) EXCEEDS $0.15/dispatch and
$2/day; execution continued solely under the human one-time spend override
recorded in the item dispatch, not as a budget PASS.

| Leg | Verdict | Evidence |
|---|---|---|
| Native marketplace path (`marketplace add` + `plugin install`) | PASS (published source only) | `native-20261002/s4n-10-claude.log:87,90` both exit 0; resolved default-branch `cb4f1245…` (`s4n-10b-claude-content.log:23,59`), NOT candidate: no pinning exists, so never candidate proof |
| Native content (skill/auditor/method-report/validator) | PASS | `s4n-10c-claude-native-content.log:45-48` all four PRESENT; validator present with vacuous usage `OK (0 report(s) checked)` (`:52`) |
| Fallback `install.sh --target claude` from candidate HEAD `25c4b97` | PASS | `s4n-10d-claude-fallback.log:13-15` exit 0, mode=symlink; refs present (17/12/10/16 files); no `settings.json` written in symlink mode (`s4n-10e-claude-fallback2.log:36`), recorded not failed |
| Installed SKILL hash lineage | RECORDED | Source worktree file (CRLF) == installed symlink target: `74ce82…` (`s4n-10e-claude-fallback2.log:38-40`); differs from Step-4 `b6936a26…` only by CRLF/LF checkout normalization (cause verified by byte dump, same note) |
| Installed validator, explicit root (candidate runtime) | PASS | True exits without pipes: bad flag 2, malformed report 1 with 10 errors, no-report 0 vacuous (`s4n-10e-claude-fallback2.log:42-48`) |
| Fresh `/sefi:audit build` | PENDING | `claude -p` exits 0 with `Not logged in · Please run /login` (`s4n-10-claude.log:106`); no model credentials exist and adding them is unauthorized |
