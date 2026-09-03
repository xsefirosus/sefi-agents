# Benchmarks -- blinded paired A/B harness

This directory holds the design, frozen cases, deterministic scorer, and out-of-process
runner for a blinded paired A/B comparison of the full sefi-agents chain against a single
strong model. It is contributor tooling. No **benchmark run** is ever triggered by CI,
the gate, or a loop -- that is literally true, not just intent. The two files the gate
does execute are `benchmarks/test_scorecard.py` (a fast offline stdlib unit test of the
SCORER, `benchmarks/scorecard.py`) and `benchmarks/test_runner.py` (the same, for the
RUNNER package `benchmarks/runner/`): zero model calls, NOT a benchmark run. Both run
under `python -m pytest` and `python -m unittest`.

The harness itself (worktree setup, model invocation, the read-only judge) is operated
per `plugins/sefi-core/skills/run-sefi-benchmark/SKILL.md`; this README is the design of
record and the schema reference the skill points at.

## Trial integrity -- enforced by benchmarks/runner/

Trial integrity is enforced by an out-of-process runner package,
`benchmarks/runner/` (`git` CLI + Python 3.11 standard library only -- no pip package,
no container runtime). The **runner process, never an arm**, observes every fact and
writes every field of every trial record. Like the scorer, it is contributor tooling:
no **benchmark run** is triggered by CI, the gate, or a loop.

### The sandbox (`benchmarks/runner/sandbox.py`)

Each trial runs in a real `git clone`, **never a `git worktree`**:

- `tempfile.mkdtemp(prefix="sefi-bench-")` -- a scratch dir OUTSIDE every repo tree and
  outside `benchmarks/results/`.
- `git clone --no-checkout --no-hardlinks --no-local <file-uri> <scratch>/repo` -- a
  three-slash `file://` URI plus `--no-local` forces real transport, so the clone gets
  its **own object store** and writes no `.git/objects/info/alternates`. `--no-checkout`
  is load-bearing: it makes the checkout below the ONLY checkout, so the host's system
  `core.autocrlf=true` never gets a first, uncontrolled pass at the tree.
- `<scratch>/repo/.gitattributes` is written with `* -text` BEFORE checkout, then
  `git -C <repo> -c core.autocrlf=false -c core.eol=lf checkout --force <pinned_ref> -- .`
  (detached) -- a system `core.autocrlf=true` cannot rewrite content on checkout.
- Teardown is `shutil.rmtree` in a `finally:`, so the scratch dir is removed on error
  and on timeout, not only on the happy path.
- `git` and `bash` are resolved by an explicit validated PATH walk (isfile + X_OK),
  never a bare name handed to `subprocess` (on Windows a bare name is resolved by
  CreateProcess, which searches System32 first and can hit a WSL relay stub).

Never a `git worktree`: a worktree shares `.git` (including `.git/info/exclude`, hooks,
and config) with its base, so there is no filesystem boundary between the arm and the
trust root. That was the withdrawn shell design's root failure.

### Out-of-process snapshot + diff (`benchmarks/runner/snapshot.py`)

`snapshot(repo)` walks the tree EXCLUDING `.git`, reads each file in **binary mode**, and
maps each POSIX relpath to `sha256(bytes)`. Binary-mode hashing plus the forced `eol=lf`
checkout makes the manifest byte-reproducible across two independent sandbox builds on
this Windows host. `diff(before, after, allowed_paths)` returns every path that changed,
was added, or was removed AND is not under an `allowed_paths` entry. An `allowed_paths`
entry matches a path exactly or as a directory prefix (`a/b` covers `a/b` and `a/b/c`,
not `a/bc`); `allowed_paths` is the case's own list from `cases.json`. The runner writes
`pre-*.manifest`, `ref-*.manifest`, and `post-*.manifest` per trial to the `--out`
directory, plus one run-level `ref.manifest` (see the integrity gate below), OUTSIDE the
sandbox, in a runner-owned dir the arm's prompt and cwd never name.

### Out-of-process route capture (`benchmarks/runner/route.py`)

The runner shells out to check-route.sh -- the security-reviewed route-evidence shim
committed on `feat/route-evidence-live` @ `8c1779c` -- as
`check-route.sh <harness> <tier> <session-record-or-thread-id>` (the 3rd positional is a
lowercase-UUID thread id or `-`, never a file path). **The arm's own output is never
parsed for route evidence.** The shim's exit code plus its single JSON stdout line map
to one boolean, `RouteResult.captured`:

- **CAPTURED** (check passes): exit 0 with status `match` or `not-applicable`; exit 1
  with status `mismatch` or `unavailable`.
- **NOT CAPTURED** (check fails, fail-closed): exit 2 (usage); exit 3 (no interpreter /
  shim skipped); exit 1 with status `invalid`; any missing / non-JSON / unparseable
  stdout line; the script absent; a raised `OSError` / `TimeoutExpired`.

`unavailable` (returned unconditionally for `claude-code`) and `not-applicable` (a
`flexible` tier) still count as CAPTURED, so a Claude Code trial stays scoreable while
the separate route-correctness axis honestly reports `model=unchecked`. There is no
env-var override for the script path; the test-only `--check-route-cmd` seam points at a
fixture and real operators never pass it.

### Runner-written records (`benchmarks/runner/record.py`)

`build_record(...)` assembles the trial dict from **runner-observed values only**:
`strategy`, `harness`, `wall_time_seconds`, `model_calls`,
`accepted` / `first_pass_accepted` / `rework_required` (from the runner re-running the
case acceptance check from a PRISTINE copy outside the sandbox, resolved by absolute path
from the base checkout -- never an arm-authored check string from the trial tree),
`case_fingerprint` (from `cases.json`), and one `route_evidence` lane. It maps an empty
`observed_model` / `observed_effort` to the status word so the value satisfies
`scorecard.py`'s charset, and OMITS `expected_model` for an ungraded lane so it reports
`model=unchecked`. `record.py` imports nothing from `arms.py` and has no code path that
reads arm stdout or the raw log. No arm-written value is an input to scoring.

`model_calls` is a **placeholder, not an observation**: in this version NO harness reports
a per-call count, so `model_calls` is emitted as a floor of `1` (one arm invocation)
purely to satisfy the scorer's route-lane invariant (`model_calls >= len(route_evidence)`).
`model_calls_delta` between arms is therefore **not a meaningful measured quantity** until
per-call telemetry is wired.

**Honest limit -- wholesale artifact forgery.** No arm-written *value* is a scoring input,
and the arm is never told the results-dir path (`arms.py` puts every arm-facing file --
prompt, session-echo, raw log -- in a private `tempfile.mkdtemp` dir torn down in a
`finally:`; the runner copies the human-readable log under `--out` only *after* the arm
has exited). But an arm dropping its *own* `trials.jsonl` somewhere on disk is **not
prevented without OS-level isolation** (a container), which this version does not use.
Mitigations: arm scratch is isolated from the results dir; the results-dir path is never
disclosed to the arm; `run.py` refuses a non-empty `--out` (SystemExit 2, never cleaned),
refuses to finalize over a pre-existing `trials.jsonl`, and unlinks any raced-in one on an
abort.

**Honest limit -- the raw-log copy window.** The human-readable raw arm log is copied out
of the arm's private scratch dir *after* the arm process exits, so a detached grandchild
of the arm could rewrite it in that window; treat the raw log as arm-influenceable
evidence, never a scoring input (nothing in `benchmarks/runner/` reads it).

### Fail-closed integrity gate (`benchmarks/runner/integrity.py`)

`verify(pre, ref, post, allowed_paths, route_result)` computes `ok = True` then
`ok = ok and <check>` for EACH of: an explicit shape guard (`pre` and `post` are
non-empty dicts, `ref` is a dict); `pre == ref`; `snapshot.diff(pre, post, allowed_paths)
== []` (no out-of-allowlist change); `route_result.captured is True`. The whole body is
wrapped in
`try: ... except Exception: return False`. There is **no `is not False`, no
`if <x>_available:` skip, no early `return True`** -- a missing manifest, an import
failure, a raised exception, or an uncaptured route all yield `False`. `record.py` sets
`integrity_ok` LAST and ONLY as `verify(...) is True`; every other outcome omits the key
and `scorecard.py` then excludes the trial.

The `ref` manifest is `snapshot()` of a **dedicated clean `git clone` at `pinned_ref`**,
built and torn down ONCE per run by `run.py` and cached for every trial. So `pre == ref`
is a real check -- it catches a per-trial clone that came out different from a known-good
baseline (a corrupted clone, an `autocrlf` leak, a disk fault) -- not a by-construction
tautology. One extra `git clone` per run (not per trial). Base-checkout integrity itself
is not enforced without OS isolation; the check script is resolved from the base checkout
by absolute path with a `relative_to` escape guard and run as an argv list (never a shell
string, never the sandbox copy).

### `trials.partial.jsonl` -> `trials.jsonl` staging (`benchmarks/runner/run.py`)

Each trial's record is staged to `<out>/trials.partial.jsonl` as it completes. The budget
pre-flight reads `benchmark_per_run_usd_cap` from `config/budget.yml` by the same
line-scan `scorecard.py` uses (no YAML dependency); an absent / non-finite / non-positive
cap **ABORTS before any arm runs**. A **real run** (no `--mock-arm`) with a non-positive
`--est-cost-per-trial` also aborts in pre-flight -- the running ceiling would be inert, so
the `$cap` could never bind; a `--mock-arm` run (zero spend by construction) may pass `0`.
A running cost ceiling then stops the matrix before a trial that would cross the cap. On
ANY abort -- budget, cost-ceiling, or a fatal mid-run error -- the runner writes
`<out>/ABORTED.md` (a fatal error's reason is `fatal: <exc>`), leaves
`trials.partial.jsonl` in place, removes any `<out>/trials.jsonl` that raced in, and
**never creates `<out>/trials.jsonl`**. Only a clean, within-budget completion of the full
matrix copies `trials.partial.jsonl` -> `trials.jsonl` (write-temp-then-rename), and only
if no `trials.jsonl` already exists there -- the runner never finalizes over a file it did
not write. The scorer is only ever pointed at `trials.jsonl`, so an aborted run has
nothing to score -- "trials so far non-scored" holds structurally. `run.py` exits 0 on a
completed OR a cleanly aborted run; **non-zero ONLY on a usage / argument error** (a bad
`--strategies` / `--harness`, an unknown case: exit 2, no output dir created).

### How to run

From the repository root (`python3` first, then `python` where `python3` is absent or a
non-working Microsoft Store stub):

```sh
python benchmarks/runner/run.py \
  --cases sh-strict-mode --strategies control,sefi-chain-sequential \
  --harness claude-code --out benchmarks/results/<date>-<slug>
```

`--mock-arm <path.py>` and `--check-route-cmd <path.sh>` are **TEST seams** (a local
Python mock arm and a check-route.sh fixture); real operators pass neither. Score the
result with
`python benchmarks/scorecard.py benchmarks/results/<date>-<slug>/trials.jsonl`.

**Ordering dependency.** check-route.sh / check-route.py live on `feat/route-evidence-live`
@ `8c1779c`, NOT on this branch. Absent that script, `route.py` reports
`captured is False`, `integrity.verify` returns `False`, and **every trial is fail-closed
non-scored**. Real positive route capture requires `feat/route-evidence-live` merged (or
this branch rebased onto it) first.

### CI wiring -- settled

No Python invocation is added to `plugins/sefi-core/scripts/ci/run-all.sh`; it stays
Python-free, matching the stance that `scorecard.py` is never wired into `run-all.sh`, a
CI job, or a loop. `gate.sh` already auto-collects `benchmarks/test_*.py` via its
`find ... -name 'test_*.py'` branch (with `--ignore=.git --ignore=.worktrees`), so
`benchmarks/test_runner.py` runs under the gate with **no `gate.sh` change**. Confirmed
on this branch: `pytest -q --collect-only --ignore=.git --ignore=.worktrees` collects
`benchmarks/test_runner.py` (65 tests, e.g.
`benchmarks/test_runner.py::EndToEndTests::test_green_run_scores_two_trials`), and
`bash plugins/sefi-core/scripts/gate.sh` prints `gate: PASSED (2 checks)` with
`ok: pytest`.

### Why the earlier shell-based approach was withdrawn

An earlier revision shipped a shell integrity checker (a fingerprint verifier + pinned
trust root). It was rejected across four review rounds for two root causes a shell script
cannot fix: a `git worktree` shares `.git` with its base (no filesystem boundary), and
`core.autocrlf=true` in this project's own Windows system git config rewrites line
endings on checkout (hash-pinning a checked-out file is then not reproducible). The
runner above closes both: a real `git clone` with its own object store, and a
`.gitattributes` + `core.eol=lf` forced checkout with binary-mode hashing.

## What is compared

For each frozen case, two arms run against the **same frozen case packet** and the
**same acceptance checks**:

- **control** -- one `high`-tier model working alone in an isolated per-trial sandbox
  (a fresh `git clone`).
- **treatment** -- the full sefi-agents chain (product-manager -> designer -> engineer
  -> qa, as routed) in its own isolated per-trial sandbox.

The arms are paired on `case_id` + `trial`. The scorecard reports treatment-minus-control
point deltas per case and in aggregate. Full deterministic paired-bootstrap confidence
intervals are deferred to a follow-up plan; this ships point deltas plus the route axis.

The per-trial sandbox is a real `git clone` with its own object store, built and torn
down by `benchmarks/runner/sandbox.py` -- it **is** the security boundary (see the
integrity section above), not merely concurrency isolation.

### Route correctness is a separate axis

An outcome win must never be able to hide a run that used the wrong model or reasoning
effort. The scorecard prints a **separate `route-correctness` block**: per lane, observed
model/effort versus expected. A trial can be accepted on outcome and still contribute to
the route-incorrect count. The two axes are never merged.

### A chain loss is a valid result

A result showing the chain **losing** on some task classes -- slower, more tokens, no
better acceptance -- is an accepted, publishable outcome. It is evidence about where the
chain does and does not pay for itself, not a harness failure to be re-run away.

### Invalid runs are retained, never deleted

If a run's reviewer verdict is REJECT (or a design defect is found after the fact), the
run's raw artifacts stay on disk under `benchmarks/results/<date>-<slug>/` with an
`INVALID.md` at its root explaining why. It is never deleted and never silently
re-run. Convention adapted from astral-orchestrator's
`benchmarks/results/2026-08-04-invalid-pilot/INVALID.md` (MIT).

### What is committed and what is not

`benchmarks/results/` is git-ignored -- raw run artifacts, worktrees, and judge
transcripts are never committed. Promotion copies exactly one file out of a run: the
`scorecard.py` output, committed as `benchmarks/published/<date>-<slug>.scorecard.txt`
(`benchmarks/published/` is tracked; it starts with just a `.gitkeep`). The design, cases,
prompts, fixtures, and scorer under `benchmarks/` are tracked; `benchmarks/results/`,
`__pycache__/`, and `*.pyc` are git-ignored (run artifacts and dev-only bytecode, never
shipped) and are also excluded from `validate-no-personal-paths.sh`'s `benchmarks/` scan.

## Frozen cases

`cases.json` freezes three cases. Each entry:

| Field | Meaning |
|---|---|
| `case_id` | Stable case name. |
| `case_fingerprint` | First 64 hex of `sha256(cat <prompt_file> <acceptance_check>)` -- prompt + check ONLY, the two-file case definition. It is retained purely as the pairing key `scorecard.py` uses: the scorer only asserts a paired control and treatment record carry the SAME value, it never recomputes it from disk. See "Recomputing a case_fingerprint" below if a case is regoldened. |
| `prompt_file` | The task prompt handed to both arms, verbatim. |
| `allowed_paths` | Paths a trial is meant to modify. **Enforced** by `benchmarks/runner/`: `snapshot.diff` flags any pre-run-to-post-run change outside these prefixes, and `integrity.verify` then withholds `integrity_ok` (see "Trial integrity" above). |
| `immutable_paths` | Files a trial is meant not to touch -- the case's own prompt, its acceptance check, and `cases.json`. Documentation of intent; the runner enforces the complement (anything not under `allowed_paths` is a violation). |
| `acceptance_check` | A deterministic shell command, exit 0 = accepted / exit 1 = not accepted. No model call, no network, no writes. Takes the trial worktree root as its argument. |

The three current cases:

- `sh-strict-mode` -- add `set -euo pipefail` to a sandbox shell script.
- `json-trailing-newline` -- pretty-print a minified JSON file with a trailing newline.
- `notes-single-h1` -- demote extra Markdown H1 headings so exactly one remains.

The files under `benchmarks/sandbox/` are the **pre-task** starting state. Every
`acceptance_check` exits 1 against that state and exits 0 only after a trial completes the
task inside its own worktree. A trial legitimately modifies its sandbox file to do the
task; a passing acceptance check on the modified file is EXPECTED.

### Recomputing a case_fingerprint

Only needed after a deliberate edit to a case's prompt or acceptance check (a
"regolden"). From the repo root:

```sh
cat benchmarks/prompts/<case_id>.md benchmarks/cases/check_<case_id>.sh \
  | sha256sum | cut -c1-64
```

Paste the 64-hex result into that case's `case_fingerprint` in `benchmarks/cases.json`,
in the same commit as the prompt/check edit.

## Trial-record schema (`trials.jsonl`)

UTF-8 JSON Lines: one complete JSON object per line, one object per trial. `schema_version`
is `1`. Required fields:

| Field | Meaning |
|---|---|
| `schema_version` | Always `1`. |
| `trial_id` | Globally unique identifier for this attempt. |
| `case_id` | The frozen case name. |
| `case_fingerprint` | The case's fingerprint. A paired control and treatment record must carry the same value. |
| `trial` | Positive integer, matched between the paired control and treatment record. |
| `strategy` | Exactly `control`, `sefi-chain`, or `sefi-chain-sequential` (see the harness matrix below). |
| `harness` | The harness the arm ran on (`claude-code`, `codex`, ...). |
| `acceptance_checks` | Non-empty list of check identifiers. The paired control and treatment record must carry the same set. |
| `accepted` | Whether the final output passed every acceptance check. |
| `first_pass_accepted` | Whether it passed before any rework. Cannot be true when `accepted` is false. |
| `rework_required` | Whether the first output needed rework. Cannot be true together with `first_pass_accepted`. |
| `wall_time_seconds` | Non-negative wall-clock duration for the whole arm. |
| `model_calls` | Never fewer than the `route_evidence` count. In this version NO harness reports a per-call count, so the runner emits it as a floor of `1` (one arm invocation) to satisfy that invariant -- it is a placeholder, not a measurement, and `model_calls_delta` is not a meaningful measured quantity yet. |
| `route_evidence` | Non-empty list of route-evidence objects (below). |

Optional fields: `input_tokens`, `output_tokens`, `quality_score` (0-100 number,
requires the boolean `quality_score_blinded`), `integrity_ok` (boolean -- see "Trial
integrity" above; ONLY `benchmarks/runner/integrity.verify` sets it, and only to `true`;
a trial it cannot verify omits the key and the scorer excludes that record), and
`cost_usd` (non-negative number -- this trial's measured
model spend in USD). Total strategy tokens are `input_tokens + output_tokens`. The
scorecard uses an optional metric only when it is present on **every** trial in the group
being aggregated; otherwise that metric prints `null`.

`scorecard.py` treats `integrity_ok` as a **required condition to contribute**: only a
trial with `integrity_ok` exactly `true` is scored. A trial with `integrity_ok: false`,
**or with the field missing, or with any other value**, is EXCLUDED from every delta AND
from the route-correctness table, and is counted on the
`excluded (integrity_ok not true): N` line (which breaks down `integrity_ok false: N` vs
`missing/other: N`). The `scored trials (integrity_ok is true): N` line reports what
remained. Absence is EXCLUDED -- never counted clean.

`scorecard.py` also prints a run-cost line: when every **scored** trial carries
`cost_usd`, `run cost $X.XX vs ceiling $15.00 [config/budget.yml]: WITHIN` (or `OVER`);
when any scored trial lacks it, `run cost: unknown (cost_usd missing on N scored
trial(s)) -- ceiling $15.00 [config/budget.yml] not checkable`; and if
`benchmark_per_run_usd_cap` is present but non-finite / non-positive / unparseable,
`run cost: ceiling unreadable [...] -- not checkable` (never a `WITHIN` verdict). The
ceiling is read from `benchmark_per_run_usd_cap` in `config/budget.yml` (falling back to
a hardcoded 15.00 only when the key is absent). Nothing BLOCKS an over-ceiling run
(`docs/BUDGET.md`); this line is the after-the-fact check.

Non-finite numbers (`NaN`, `Infinity`, `-Infinity`) are rejected at parse time -- the
scorer exits 2 with a one-line `ERROR:` rather than scoring them. Every
attacker-influenceable text field (`case_id`, `harness`, `strategy`, and every
`route_evidence` string) must match `^[A-Za-z0-9][A-Za-z0-9 ._:/-]{0,63}$`; a value with
a newline, control char, quote, or backslash is rejected the same way, so a crafted
`trials.jsonl` cannot forge a route-correctness row or inject an ANSI escape.

**Missing telemetry stays `null`, never `0`.** A judge that could not be reached, a
harness that reports no token usage -- record the field as `null` or omit it. Do not
write `0`.

Each `route_evidence` object:

```json
{
  "role": "implementer",
  "model": "observed-model-id",
  "effort": "observed-effort",
  "expected_model": "expected-model-id",
  "expected_effort": "expected-effort",
  "task_id": "globally-unique-lane-id"
}
```

`role`, `model`, `effort`, `expected_effort`, and `task_id` are required. `task_id` must
be globally unique across the whole file. `expected_model` is **optional**: the route
axis needs an expected model to grade against, so the scorecard checks it when present
and reports the lane as `model=unchecked` when absent. A judge's own lane, if recorded,
goes in its own record or is kept out of `route_evidence`; judge tokens and judge time
are always tracked separately from the arm totals.

### Hand-authoring `trials.jsonl`

`benchmarks/runner/run.py` writes `trials.jsonl` for an out-of-process run. The trial
file may still be authored by hand (or by a thin operator script) for a manual run, one
JSON object per line, from outside any trial sandbox -- but a hand-authored record can
never carry `integrity_ok`, so it always scores zero:

1. Run each arm, record its wall time, model calls, and -- when the harness exposes them --
   token counts. Missing counts stay `null`.
2. Run the case's `acceptance_check` against the arm's output tree for
   `first_pass_accepted`; allow one rework pass if the chain's own review calls for it;
   re-run for `accepted`.
3. Record one `route_evidence` object per lane: the observed model and effort, plus
   `expected_effort` and (when known) `expected_model`.
4. Pair a `control` record and a treatment record on `case_id` + `trial`; give them the
   same `case_fingerprint` and the same `acceptance_checks` set.
5. Do **not** hand-set `integrity_ok` -- only `benchmarks/runner/integrity.verify` is
   entitled to set it.
6. Append the line; never rewrite an earlier line.

### Minimal example

```jsonl
{"schema_version":1,"trial_id":"c1","case_id":"demo","case_fingerprint":"abc","trial":1,"strategy":"control","harness":"claude-code","acceptance_checks":["k"],"accepted":true,"first_pass_accepted":true,"rework_required":false,"wall_time_seconds":20,"model_calls":1,"route_evidence":[{"role":"solo","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"c1-solo"}]}
{"schema_version":1,"trial_id":"x1","case_id":"demo","case_fingerprint":"abc","trial":1,"strategy":"sefi-chain","harness":"claude-code","acceptance_checks":["k"],"accepted":true,"first_pass_accepted":true,"rework_required":false,"wall_time_seconds":45,"model_calls":3,"route_evidence":[{"role":"planner","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"x1-p"},{"role":"implementer","model":"m-high","effort":"mid","expected_model":"m-high","expected_effort":"mid","task_id":"x1-i"},{"role":"reviewer","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"x1-r"}]}
```

Both example records omit `integrity_ok`, so this hand-authored pair scores zero trials --
only a trial verified by `benchmarks/runner/integrity.verify` carries the key.

## Harness matrix and the dispatch-asymmetry rule

Each harness is invoked headless per the row already in
`plugins/sefi-core/skills/sefi-orchestration/references/harness-actions.md`
("Invoke the harness headless": Claude Code per its own line, `opencode run`,
`codex exec`, Hermes HTTP gateway). Dispatch capability is **not uniform**
(`harness-actions.md:11,17-18`): Codex needs `multi_agent = true` or it runs the roster
sequentially; a harness with no subagent tool "executes the roster sequentially in one
context".

**Dispatch-asymmetry rule.** Where the chain runs with real parallel dispatch, the arm is
`strategy: sefi-chain`. Where it runs sequentially in one context, it is a **separately
labelled** arm, `strategy: sefi-chain-sequential`. The two are never silently equated; the
scorecard keeps them in distinct rows everywhere.

| Harness | Order | Status | Reason |
|---|---|---|---|
| Claude Code | first | supported | Reference/dev harness. `model-map.yml:40` gives concrete model ids so route-evidence is meaningful; the platform constraint at `harness-actions.md:20-27` is already live-verified there. |
| Codex | second | supported | Concrete model ids; `codex exec` headless per `harness-actions.md:76`. Runs as `sefi-chain` only with `multi_agent = true`; otherwise `sefi-chain-sequential`. |
| OpenCode | -- | DEFERRED | Its tiers resolve to the `flexible` sentinel (`model-map.yml:87-89,106-108`): the control arm has no fixed model identity, so a "single strong model vs chain" pairing is undefined until a human pins a model. Recorded as UNKNOWN, not guessed. |
| Hermes | -- | DEFERRED | Same as OpenCode: tiers resolve to `flexible`; no fixed control-arm model identity. UNKNOWN, not guessed. |

## The scorer -- `scorecard.py`

Minimal deterministic scorer. **Python 3 standard library only** (developed and verified
on Python 3.11.15). It makes no model call, no dispatch, no network request, and writes
nothing. It must never be added to `plugins/sefi-core/scripts/ci/run-all.sh`, a CI job, a
loop, or a dispatched-agent path -- same stance astral-orchestrator takes on `tiktoken` /
`uv`.

Run it from the repository root:

```sh
python3 benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl
python3 benchmarks/scorecard.py --help
```

On a host where `python3` is absent or a non-working stub (some Windows setups ship a
Microsoft Store stub that only prints an install hint), use `python` instead:

```sh
python benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl
```

Output has a header (including the `scored trials (integrity_ok is true): N`,
`excluded (integrity_ok not true): N ...`, and `run cost ...` lines), an **aggregate-delta
block** (per case and overall, `sefi-chain` and `sefi-chain-sequential` each versus
`control`, kept distinct), and a **separate `route-correctness` block** built from the
scored trials only. The `source:` line and every `ERROR:` line print the trials-file
basename only -- never the absolute invocation path. The scorer is
deterministic: same input gives byte-identical output (it writes raw UTF-8 with LF
endings, so this holds on Windows too). It exits 0 on a valid data set, 2 with a one-line
`ERROR:` on a malformed one, and never emits a traceback for malformed input.

### Determinism fixture and the scorer unit test

`benchmarks/fixtures/trials.jsonl` is a hand-authored data set and
`benchmarks/fixtures/expected-scorecard.txt` is its committed expected output.
`benchmarks/test_scorecard.py` is a fast offline stdlib unit test of the SCORER only
(zero model calls, NOT a benchmark run) that pins the determinism check plus the
crafted-input regressions; it runs under both `python -m pytest` and
`python -m unittest`. It is one of two benchmark files `gate.sh` executes
(`benchmarks/test_runner.py` is the other -- see "Trial integrity" above). The
determinism check by hand:

```sh
python3 benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl > /tmp/a
python3 benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl > /tmp/b
diff /tmp/a /tmp/b                                   # byte-identical
diff benchmarks/fixtures/expected-scorecard.txt /tmp/a
```

The fixture sets `"integrity_ok": true` on all 14 records **only so the scorer has data
to score in the test** -- a hand-authored trial file cannot carry that field, and a
runner trial carries it only when `benchmarks/runner/integrity.verify` passed
(see "Trial integrity" above). The fixture deliberately includes a case where `sefi-chain`
wins on outcome while one lane ran a wrong model, so the route-incorrect count stays
non-zero -- the route axis is genuinely independent of the outcome axis.

## Reading a scorecard honestly

- The scorer summarises the trials it was given. It does not establish general model
  superiority, causation, cost beyond the recorded measures, or statistical significance.
- A `null` is missing data, not a zero.
- The route-correctness block is authoritative for "did the right model run"; the delta
  block is authoritative for "was the outcome better". Cite both.
- Trial integrity is enforced out-of-process by `benchmarks/runner/` (real `git clone`
  sandbox, out-of-process snapshot + diff, out-of-process route capture, fail-closed
  `integrity.verify`). A hand-authored `trials.jsonl` remains unverified and scores zero.
- Benchmark results are cited from `docs/METRICS-PROVENANCE.md`. The harness is
  out-of-loop and its spend is separately authorized -- see `docs/BUDGET.md`.
