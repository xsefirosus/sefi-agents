# Benchmarks -- blinded paired A/B harness

This directory holds the design, frozen cases, and deterministic scorer for a blinded
paired A/B comparison of the full sefi-agents chain against a single strong model. It is
contributor tooling. No **benchmark run** is ever triggered by CI, the gate, or a loop --
that is literally true, not just intent. The one file the gate does execute is
`benchmarks/test_scorecard.py`: a fast offline standard-library unit test of the SCORER
only (`benchmarks/scorecard.py`), zero model calls, NOT a benchmark run. It runs under
both `python -m pytest` and `python -m unittest`.

The harness itself (worktree setup, model invocation, the read-only judge) is operated
per `plugins/sefi-core/skills/run-sefi-benchmark/SKILL.md`; this README is the design of
record and the schema reference the skill points at.

## Trial integrity -- NOT IMPLEMENTED in this version

**Nothing in this version verifies that a benchmark arm behaved.** There is no filesystem
sandbox, no out-of-process snapshot-and-diff, and no post-run path check. An arm could
edit its own acceptance check, rewrite the answer key, or change files outside its
declared `allowed_paths`, and this harness would not notice. `allowed_paths` and
`immutable_paths` in `cases.json` and the prompts are **advisory documentation** of what
each case is meant to permit -- they describe intent, they do not enforce it.

Until the sandboxed runner exists, the operator MUST run every acceptance check from a
**pristine copy of `benchmarks/cases/`** (and `cases.json`) the **arm could not write
to** -- resolved by absolute path from the base checkout, **never from the trial
worktree** -- because an arm can rewrite its own `acceptance_check` string and its
`check_<id>.sh` and the harness will not notice, and the operator would otherwise be
executing the arm's code in the operator's own shell (a cross-session
privilege-escalation risk, not just a bad-score risk).

The `integrity_ok` field still exists in the trial-record schema and `scorecard.py` is
**fail-closed** on it: a trial is scored only when `integrity_ok` is exactly `true`; a
record that is missing the field, or carries any other value, is excluded from every
delta AND from the route-correctness table and is counted on the
`excluded (integrity_ok not true): N` line. Because nothing in this version ever *sets*
`integrity_ok`, **the records a real run produces will not carry it, so a real run scores
zero trials.** That is deliberate: an unverified score is worse than no score. The
`benchmarks/fixtures/trials.jsonl` determinism fixture sets `"integrity_ok": true` on
every record **only so the scorer has something to score in its unit test** -- a real run
will not, and must not, hand-set it.

### What a future sandboxed runner must provide

Trial integrity is a requirement deferred to a future component. To set `integrity_ok:
true` honestly it must provide **all** of:

1. **A real filesystem sandbox per trial.** A container, or at minimum a separate `git
   clone` with its own `.git` directory. **Never a `git worktree`**: a worktree shares
   the base checkout's `.git`, including `.git/info/exclude`, so there is no filesystem
   boundary between the arm and the trust root -- an arm with write access to its worktree
   can reach objects and ignore rules the base also sees.
2. **An out-of-process snapshot + diff**, taken from outside the arm's reach (the host,
   or the container manager), comparing the trial tree before and after the arm runs and
   flagging any change outside `allowed_paths`. The arm must never be able to run, read,
   or tamper with the checker.
3. **Line-ending-safe hashing.** This project's own Windows clone path sets
   `core.autocrlf=true` in system git config, which rewrites line endings on checkout, so
   a naive `sha256` of a checked-out file is not reproducible across platforms. The runner
   needs a committed `.gitattributes` pinning the relevant paths to `-text` (or `text
   eol=lf`), or binary-safe hashing that reads bytes without git's smudge filter.
4. **Operator-written trial records.** Every `trials.jsonl` record is written by the
   operator from outside the trial worktree. `integrity_ok` is set from the checker's exit
   code (0 -> true, non-zero -> false); it is NEVER copied from anything the arm produced.

### Why the earlier shell-based approach was withdrawn

An earlier revision shipped a shell integrity checker (a fingerprint verifier + pinned
trust root). It was rejected across four review rounds for two root causes a shell script
cannot fix:

- **A `git worktree` shares `.git` (including `.git/info/exclude`) with its base.** There
  is no filesystem boundary, so a base-vs-worktree agreement check can be satisfied by an
  identical edit made in both trees, and even a pinned-constant trust root sits in a
  directory the arm can write to. Closing this needs a real sandbox (requirement 1), not
  a cleverer hash.
- **`core.autocrlf=true` in this project's own Windows system git config** rewrites line
  endings on checkout, so hash-pinning a checked-out file is not reproducible across the
  platforms the project is developed on. Closing this needs committed `.gitattributes` or
  byte-level hashing (requirement 3).

The scorer, the frozen cases, the acceptance checks, and this design doc ship without the
checker. Trial integrity ships when the sandboxed runner does.

## What is compared

For each frozen case, two arms run against the **same frozen case packet** and the
**same acceptance checks**:

- **control** -- one `high`-tier model working alone in an isolated git worktree.
- **treatment** -- the full sefi-agents chain (product-manager -> designer -> engineer
  -> qa, as routed) in its own isolated git worktree.

The arms are paired on `case_id` + `trial`. The scorecard reports treatment-minus-control
point deltas per case and in aggregate. Full deterministic paired-bootstrap confidence
intervals are deferred to a follow-up plan; this ships point deltas plus the route axis.

The per-trial worktree is for **isolation of concurrent trials, not a security boundary**
(see the integrity section above).

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
| `allowed_paths` | Paths a trial is meant to modify. **Advisory** -- nothing enforces it in this version (see "Trial integrity" above). |
| `immutable_paths` | Files a trial is meant not to touch -- the case's own prompt, its acceptance check, and `cases.json`. **Advisory** -- nothing enforces it in this version. |
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
| `model_calls` | Number of model calls (never fewer than the `route_evidence` count). |
| `route_evidence` | Non-empty list of route-evidence objects (below). |

Optional fields: `input_tokens`, `output_tokens`, `quality_score` (0-100 number,
requires the boolean `quality_score_blinded`), `integrity_ok` (boolean -- see "Trial
integrity" above; nothing in this version sets it, so a real run omits it and the scorer
excludes every such record), and `cost_usd` (non-negative number -- this trial's measured
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

Until a real runner exists, the trial file is written by hand (or by a thin operator
script), one JSON object per line, from outside any trial worktree:

1. Run each arm, record its wall time, model calls, and -- when the harness exposes them --
   token counts. Missing counts stay `null`.
2. Run the case's `acceptance_check` against the arm's output tree for
   `first_pass_accepted`; allow one rework pass if the chain's own review calls for it;
   re-run for `accepted`.
3. Record one `route_evidence` object per lane: the observed model and effort, plus
   `expected_effort` and (when known) `expected_model`.
4. Pair a `control` record and a treatment record on `case_id` + `trial`; give them the
   same `case_fingerprint` and the same `acceptance_checks` set.
5. Do **not** set `integrity_ok` -- there is nothing in this version entitled to set it.
6. Append the line; never rewrite an earlier line.

### Minimal example

```jsonl
{"schema_version":1,"trial_id":"c1","case_id":"demo","case_fingerprint":"abc","trial":1,"strategy":"control","harness":"claude-code","acceptance_checks":["k"],"accepted":true,"first_pass_accepted":true,"rework_required":false,"wall_time_seconds":20,"model_calls":1,"route_evidence":[{"role":"solo","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"c1-solo"}]}
{"schema_version":1,"trial_id":"x1","case_id":"demo","case_fingerprint":"abc","trial":1,"strategy":"sefi-chain","harness":"claude-code","acceptance_checks":["k"],"accepted":true,"first_pass_accepted":true,"rework_required":false,"wall_time_seconds":45,"model_calls":3,"route_evidence":[{"role":"planner","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"x1-p"},{"role":"implementer","model":"m-high","effort":"mid","expected_model":"m-high","expected_effort":"mid","task_id":"x1-i"},{"role":"reviewer","model":"m-high","effort":"high","expected_model":"m-high","expected_effort":"high","task_id":"x1-r"}]}
```

Both example records omit `integrity_ok`, so this pair scores zero trials in this version --
exactly the intended fail-closed behaviour for a real run.

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
`python -m unittest` and is the one benchmark file `gate.sh` executes. The determinism
check by hand:

```sh
python3 benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl > /tmp/a
python3 benchmarks/scorecard.py benchmarks/fixtures/trials.jsonl > /tmp/b
diff /tmp/a /tmp/b                                   # byte-identical
diff benchmarks/fixtures/expected-scorecard.txt /tmp/a
```

The fixture sets `"integrity_ok": true` on all 14 records **only so the scorer has data
to score in the test** -- a real run does not set that field and would score zero trials
(see "Trial integrity" above). The fixture deliberately includes a case where `sefi-chain`
wins on outcome while one lane ran a wrong model, so the route-incorrect count stays
non-zero -- the route axis is genuinely independent of the outcome axis.

## Reading a scorecard honestly

- The scorer summarises the trials it was given. It does not establish general model
  superiority, causation, cost beyond the recorded measures, or statistical significance.
- A `null` is missing data, not a zero.
- The route-correctness block is authoritative for "did the right model run"; the delta
  block is authoritative for "was the outcome better". Cite both.
- In this version, trial integrity is unverified: a score stands only as far as you trust
  the arms did not tamper with their own checks or files.
- Benchmark results are cited from `docs/METRICS-PROVENANCE.md`. The harness is
  out-of-loop and its spend is separately authorized -- see `docs/BUDGET.md`.
