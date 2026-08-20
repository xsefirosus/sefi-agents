## Objective
Build a new standalone checkout API at D:\Projects\checkout-demo (a NEW project -- the
directory does not exist as of 2026-08-19, verified by listing D:\Projects; do NOT build
inside D:\Projects\Sefi-Agents). Stack is locked by goal intake: Python 3 stdlib only
(http.server + unittest + urllib -- zero dependencies, no pip installs). Exactly one
endpoint: POST /charge, which records a simulated charge exactly once per
`Idempotency-Key` even when the same request is retried (the refresh/connection-loss
double-charge trigger). Chosen mechanism, Approach A: an explicit `Idempotency-Key`
header plus an in-memory ledger; a replay with the same key returns the stored result
without charging again. Approach B (request-body fingerprint as implicit key) is
documented and rejected in Risks. Verification is one deterministic command the
qa-engineer runs: `python tests/verify_idempotency.py`.

## Steps
- [x] 1. Scaffold the new project and write the RED test. Create the directory D:\Projects\checkout-demo (it does not exist today) and run `git init` inside it. Write `tests/verify_idempotency.py` encoding the full contract: it inserts the parent dir on sys.path and `import app`; starts `ThreadingHTTPServer(("127.0.0.1", 0), ...)` (port 0 = OS-assigned free port) on a background thread; then asserts, in order: (a) first POST /charge with header `Idempotency-Key: key-1` and body `{"amount": 1000, "currency": "usd", "customer_id": "cust_1"}` returns 201 with a `charge_id`; (b) a second identical POST with the same key returns 200, the SAME `charge_id`, and header `Idempotency-Replayed: true`; (c) `app.ledger` holds exactly one record; (d) a POST with a different key `key-2` and the same body returns 201 and `app.ledger` holds exactly two records; (e) a POST with no `Idempotency-Key` header returns 400; (f) a POST with malformed JSON body returns 400. The script prints "PASS: same key replayed charges once" and exits 0 only when every assertion holds; otherwise it prints the failing assertion and exits 1. (needs: -)
- [x] 2. Run the RED test from D:\Projects\checkout-demo: `python tests/verify_idempotency.py`. Expected: FAIL with `ImportError: cannot import name 'app'` -- the test is genuinely red, not accidentally green. (needs: 1)
- [x] 3. Implement `app.py` (single file, stdlib only) per this exact contract: module-level `ledger = {}` and a `threading.Lock` guarding it; `ThreadingHTTPServer` handler accepts POST /charge only (any other method or path -> 405); parse the JSON body; require a non-empty `Idempotency-Key` header (missing/empty -> 400 `{"error": "Idempotency-Key header required"}`); validate `amount` is a positive int and `currency`/`customer_id` are non-empty strings (violation -> 400 `{"error": "<reason>"}`); then, under the lock: if the key already exists in `ledger`, respond 200 with the stored response body plus header `Idempotency-Replayed: true` (no new charge); if the key is new, build `charge_id = "chg_" + uuid4().hex`, store the full record in `ledger`, and respond 201 with `{"charge_id": ..., "status": "charged", "amount": ..., "currency": ..., "customer_id": ...}`. (needs: 2)
- [x] 4. Run the GREEN test from D:\Projects\checkout-demo: `python tests/verify_idempotency.py`. Expected: exits 0 and prints "PASS: same key replayed charges once". If any assertion fails, fix `app.py` and re-run until green. (needs: 3)
- [x] 5. Commit the green state in D:\Projects\checkout-demo: `git add app.py tests/verify_idempotency.py && git commit -m "feat: idempotent POST /charge (stdlib only)"`. (needs: 4)

## Files Touched
D:\Projects\checkout-demo\app.py (created); D:\Projects\checkout-demo\tests\verify_idempotency.py (created)

## Requires Tools
python (3.8+, stdlib only -- no pip installs), git

## Risks
- The ledger is in-memory: a server restart forgets all keys, so a client retrying after a restart can be charged again. Acceptable for this demo, but the plan deliberately does not claim durability; a real provider integration needs a persistent store.
- The fix only helps if the client actually resends the same `Idempotency-Key` on retry. The API side is safe; the checkout page keeping the key across refresh is the other half and is out of scope.
- The charge is simulated (a ledger append), not a real payment; provider-side idempotency (e.g. Stripe's own key) is not exercised.
- Approach B (request-body fingerprint as the implicit key) was rejected: two legitimately identical orders (same amount + customer) would collapse into one charge -- a false dedupe that under-charges. Approach A costs one header from the client and keeps replay semantics exact; that tradeoff was accepted.
- Thread safety is a single `threading.Lock` in one process; a multi-instance deployment would double-charge across instances and is out of scope.
- Memory: no prior decisions constrain this plan -- memory/decisions/ does not exist in D:\Projects\Sefi-Agents (verified 2026-08-19).

## Done Criteria
From D:\Projects\checkout-demo, `python tests/verify_idempotency.py` exits 0 and prints "PASS: same key replayed charges once", proving: the same request body with the same `Idempotency-Key` sent twice records exactly one charge (assertions a-c), a different key records a separate charge (d), and missing-key/malformed requests are rejected (e-f). Re-running the command is safe: each run starts its own server on an OS-assigned free port and inspects `app.ledger` in-process.
