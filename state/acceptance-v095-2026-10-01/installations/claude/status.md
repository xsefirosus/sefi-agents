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
