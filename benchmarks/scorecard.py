#!/usr/bin/env python3
"""Deterministic scorer for the blinded paired A/B benchmark harness.

Reads a JSONL trial-record file (schema in benchmarks/README.md) and prints a plain-text
scorecard: paired treatment-minus-control deltas per case and in aggregate, plus a
SEPARATE route-correctness table so an outcome win cannot mask a wrong-model run.

Dev-only contributor tooling. Standard library only. It never starts a model, dispatches
an agent, writes a file, or reaches the network. It must never run inside run-all.sh, a
CI job, a loop, or a dispatched-agent path.

`benchmarks/test_scorecard.py` is a fast offline stdlib unit test of THIS SCORER only --
zero model calls, NOT a benchmark run. A real benchmark run is never triggered by CI, the
gate, or a loop.

Full deterministic paired-bootstrap confidence intervals are deferred to a follow-up
plan; this ships point deltas plus the route axis only.

Input contract: exit 0 == a valid data set was scored; exit 2 with a single-line
`ERROR:` on stderr == the input was malformed. There is no traceback path for malformed
input, and no non-finite number (`NaN` / `Infinity` / `-Infinity`) is ever accepted.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

SCHEMA_VERSION = 1
# config/budget.yml key: benchmark_per_run_usd_cap. Operator-tracked ceiling for one
# benchmark run; nothing BLOCKS an over-ceiling run (docs/BUDGET.md). Kept in sync with
# config/budget.yml; _read_ceiling() prefers the live file and falls back to this.
BENCHMARK_CEILING_KEY = "benchmark_per_run_usd_cap"
DEFAULT_BENCHMARK_CEILING_USD = 15.00
CONTROL = "control"
TREATMENTS = ("sefi-chain", "sefi-chain-sequential")
STRATEGIES = (CONTROL,) + TREATMENTS
STRATEGY_REPORT_ORDER = (CONTROL, "sefi-chain", "sefi-chain-sequential")

REQUIRED_FIELDS = (
    "schema_version", "trial_id", "case_id", "case_fingerprint", "trial", "strategy",
    "harness", "acceptance_checks", "accepted", "first_pass_accepted", "rework_required",
    "wall_time_seconds", "model_calls", "route_evidence",
)
OPTIONAL_FIELDS = (
    "input_tokens", "output_tokens", "quality_score", "quality_score_blinded",
    "integrity_ok", "cost_usd",
)
ROUTE_REQUIRED = ("role", "model", "effort", "expected_effort", "task_id")
ROUTE_TEXT_FIELDS = ("role", "model", "effort", "expected_effort", "task_id", "expected_model")
# expected_model is an optional per-lane field. Step 17's inline schema omits it; step 20
# needs "observed vs expected model" for the route axis. When present it is checked; when
# absent the lane's model is reported but not graded (status carries "model=unchecked").

# FIX B (security HIGH): every attacker-influenceable text field -- a real run's
# route_evidence is written by the harness from raw model output -- is validated against
# this strict charset BEFORE it is rendered or used as a grouping key. No newline, tab,
# control char, quote, or backslash can pass, so a crafted trials.jsonl cannot forge a
# route-correctness row or inject an ANSI escape sequence into the scorecard. `fullmatch`
# (not `$`) is deliberate: `$` would accept a trailing newline.
_TEXT_FIELD_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._:/-]{0,63}")


class _NonFinite(Exception):
    """Internal: a JSON number token was NaN / Infinity / -Infinity or overflowed."""


def _reject_constant(_const: str) -> float:
    raise _NonFinite()


def _finite_float(token: str) -> float:
    value = float(token)
    if not math.isfinite(value):
        raise _NonFinite()
    return value


class BenchmarkError(ValueError):
    """Raised for an invalid or incomparable trial data set."""


def _fail(msg: str) -> "BenchmarkError":
    return BenchmarkError(msg)


def load_trials(path: Path) -> list[dict]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        # FIX (security LOW / QA): the leak boundary is basename-only. str(OSError)
        # embeds the absolute path; use strerror so stderr matches the `source:` line.
        detail = exc.strerror or exc.__class__.__name__
        raise _fail(f"cannot read {path.name}: {detail}") from exc
    trials: list[dict] = []
    seen_trial_ids: set[str] = set()
    seen_task_ids: set[str] = set()
    for lineno, line in enumerate(raw.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            rec = json.loads(
                stripped, parse_constant=_reject_constant, parse_float=_finite_float
            )
        except _NonFinite:
            raise _fail(f"line {lineno}: non-finite number not allowed") from None
        except json.JSONDecodeError as exc:
            raise _fail(f"line {lineno}: not valid JSON ({exc.msg})") from exc
        if not isinstance(rec, dict):
            raise _fail(f"line {lineno}: record is not a JSON object")
        _validate_record(rec, lineno, seen_trial_ids, seen_task_ids)
        trials.append(rec)
    if not trials:
        raise _fail(f"{path.name}: no trial records found")
    _validate_pairs(trials)
    return trials


def _validate_record(rec: dict, lineno: int, trial_ids: set[str], task_ids: set[str]) -> None:
    missing = [f for f in REQUIRED_FIELDS if f not in rec]
    if missing:
        raise _fail(f"line {lineno}: missing required field(s): {', '.join(missing)}")
    unknown = set(rec) - set(REQUIRED_FIELDS) - set(OPTIONAL_FIELDS)
    if unknown:
        # FIX (security MEDIUM): attacker-controlled JSON keys are rendered with !r so a
        # key bearing a newline / ANSI / a forged second "ERROR:" line cannot break out of
        # the single-line error. repr() escapes every control char.
        raise _fail(
            f"line {lineno}: unknown field(s): "
            f"{', '.join(repr(k) for k in sorted(unknown))}"
        )
    # FIX E (security MEDIUM): pin every field's type before it is used. A list/dict where
    # a scalar belongs must fail with a one-line ERROR and exit 2 -- never an uncaught
    # TypeError + traceback (unhashable dict as a grouping key was the reported crash).
    for name, kind, tname in (
        ("schema_version", int, "an integer"),
        ("trial_id", str, "a string"),
        ("case_id", str, "a string"),
        ("case_fingerprint", str, "a string"),
        ("trial", int, "an integer"),
        ("strategy", str, "a string"),
        ("harness", str, "a string"),
        ("accepted", bool, "a boolean"),
        ("first_pass_accepted", bool, "a boolean"),
        ("rework_required", bool, "a boolean"),
    ):
        value = rec[name]
        if (isinstance(value, bool) != (kind is bool)) or not isinstance(value, kind):
            raise _fail(f"line {lineno}: field {name!r} must be {tname}")
    # FIX B (security HIGH): strict charset on every attacker-influenceable text field
    # before it reaches output or a grouping key.
    for name in ("trial_id", "case_id", "case_fingerprint", "harness", "strategy"):
        if not _TEXT_FIELD_RE.fullmatch(rec[name]):
            raise _fail(f"line {lineno}: field {name!r} has an invalid value")
    if rec["schema_version"] != SCHEMA_VERSION:
        raise _fail(f"line {lineno}: schema_version must be {SCHEMA_VERSION}")
    if rec["strategy"] not in STRATEGIES:
        raise _fail(f"line {lineno}: strategy must be one of {', '.join(STRATEGIES)}")
    tid = rec["trial_id"]
    if not isinstance(tid, str) or not tid.strip():
        raise _fail(f"line {lineno}: trial_id must be a non-empty string")
    if tid in trial_ids:
        raise _fail(f"line {lineno}: duplicate trial_id {tid!r}")
    trial_ids.add(tid)
    if not isinstance(rec["trial"], int) or rec["trial"] < 1:
        raise _fail(f"line {lineno}: trial must be a positive integer")
    for flag in ("accepted", "first_pass_accepted", "rework_required"):
        if not isinstance(rec[flag], bool):
            raise _fail(f"line {lineno}: {flag} must be a boolean")
    if rec["first_pass_accepted"] and not rec["accepted"]:
        raise _fail(f"line {lineno}: first_pass_accepted cannot be true when accepted is false")
    if rec["first_pass_accepted"] and rec["rework_required"]:
        raise _fail(f"line {lineno}: first_pass_accepted and rework_required cannot both be true")
    for num in ("wall_time_seconds", "model_calls"):
        if not isinstance(rec[num], (int, float)) or isinstance(rec[num], bool) or rec[num] < 0:
            raise _fail(f"line {lineno}: {num} must be a non-negative number")
    checks = rec["acceptance_checks"]
    if not isinstance(checks, list) or not checks or not all(isinstance(c, str) for c in checks):
        raise _fail(f"line {lineno}: acceptance_checks must be a non-empty list of strings")
    for opt in ("input_tokens", "output_tokens", "quality_score"):
        if opt in rec:
            val = rec[opt]
            if not isinstance(val, (int, float)) or isinstance(val, bool) or val < 0:
                raise _fail(f"line {lineno}: {opt} must be a non-negative number when present")
    if "quality_score" in rec and not isinstance(rec.get("quality_score_blinded"), bool):
        raise _fail(f"line {lineno}: quality_score requires boolean quality_score_blinded")
    if "integrity_ok" in rec and not isinstance(rec["integrity_ok"], bool):
        raise _fail(f"line {lineno}: field 'integrity_ok' must be a boolean")
    if "cost_usd" in rec:
        cost = rec["cost_usd"]
        if not isinstance(cost, (int, float)) or isinstance(cost, bool) or cost < 0:
            raise _fail(f"line {lineno}: field 'cost_usd' must be a non-negative number")
    routes = rec["route_evidence"]
    if not isinstance(routes, list) or not routes:
        raise _fail(f"line {lineno}: route_evidence must be a non-empty list")
    for route in routes:
        if not isinstance(route, dict):
            raise _fail(f"line {lineno}: each route_evidence entry must be an object")
        rmiss = [f for f in ROUTE_REQUIRED if f not in route]
        if rmiss:
            raise _fail(f"line {lineno}: route_evidence missing {', '.join(rmiss)}")
        runknown = set(route) - set(ROUTE_REQUIRED) - {"expected_model"}
        if runknown:
            # FIX (security MEDIUM): render attacker-controlled keys with !r -- see the
            # top-level unknown-field path above.
            raise _fail(
                f"line {lineno}: route_evidence unknown field(s): "
                f"{', '.join(repr(k) for k in sorted(runknown))}"
            )
        # FIX E + FIX B: type-pin then charset-check every route_evidence text field before
        # it is rendered or used as a grouping key (role) or set member (task_id). A real
        # run's route_evidence is written by the harness from raw model output.
        for rname in ROUTE_TEXT_FIELDS:
            if rname == "expected_model" and route.get("expected_model") is None:
                continue
            rvalue = route[rname]
            if not isinstance(rvalue, str):
                raise _fail(f"line {lineno}: field {rname!r} must be a string")
            if not _TEXT_FIELD_RE.fullmatch(rvalue):
                raise _fail(f"line {lineno}: field {rname!r} has an invalid value")
        task_id = route["task_id"]
        if task_id in task_ids:
            raise _fail(f"line {lineno}: route task_id {task_id!r} reused (must be globally unique)")
        task_ids.add(task_id)
    if len(routes) > rec["model_calls"]:
        raise _fail(f"line {lineno}: model_calls ({rec['model_calls']}) is below route_evidence count ({len(routes)})")


def _validate_pairs(trials: list[dict]) -> None:
    by_key: dict[tuple, dict] = {}
    for rec in trials:
        key = (rec["case_id"], rec["trial"], rec["strategy"])
        if key in by_key:
            raise _fail(f"duplicate ({rec['case_id']}, trial {rec['trial']}, {rec['strategy']}) record")
        by_key[key] = rec
    for (case_id, trial, strategy), rec in by_key.items():
        if strategy == CONTROL:
            continue
        control = by_key.get((case_id, trial, CONTROL))
        if control is None:
            continue
        if set(rec["acceptance_checks"]) != set(control["acceptance_checks"]):
            raise _fail(
                f"{case_id} trial {trial}: {strategy} and control have different acceptance_checks"
            )
        if rec["case_fingerprint"] != control["case_fingerprint"]:
            raise _fail(
                f"{case_id} trial {trial}: {strategy} and control have different case_fingerprint"
            )


# Sentinel distinct from a parsed float and from None: the key was simply not in the
# file, so the documented DEFAULT_BENCHMARK_CEILING_USD fallback applies. `None` from
# _parse_ceiling means the OPPOSITE -- the key WAS present but its value is unusable
# (non-numeric, overflowed to non-finite, or <= 0), which must never be treated as a
# usable ceiling and must never yield a "WITHIN" verdict.
_CEILING_KEY_ABSENT = object()


def _parse_ceiling(text: str):
    """Return the positive, finite USD ceiling parsed from budget.yml `text`.

    Returns `_CEILING_KEY_ABSENT` when the key does not appear at all, and `None` when the
    key IS present but its value is non-numeric, overflows to a non-finite float, or is
    not strictly positive. Only a strictly positive finite float is returned as a number.
    """
    for line in text.splitlines():
        m = re.match(
            r"\s*" + re.escape(BENCHMARK_CEILING_KEY) + r"\s*:\s*([0-9]+(?:\.[0-9]+)?)",
            line,
        )
        if m:
            try:
                value = float(m.group(1))
            except (ValueError, OverflowError):
                return None
            if not math.isfinite(value) or value <= 0:
                return None
            return value
    return _CEILING_KEY_ABSENT


def _read_ceiling() -> tuple[float | None, str]:
    """Return (ceiling_usd_or_None, source). Cheap line-scan of config/budget.yml for
    `benchmark_per_run_usd_cap: <n>` -- no YAML dependency.

    - key present, value a positive finite number -> (n, "config/budget.yml")
    - key or file absent -> (DEFAULT_BENCHMARK_CEILING_USD, "scorecard.py default ...")
    - key present but non-finite / non-positive / unparseable -> (None, "... unreadable")
      and render() then prints an explicit "ceiling unreadable" cost line, NEVER "WITHIN".
    """
    cfg = Path(__file__).resolve().parent.parent / "config" / "budget.yml"
    try:
        parsed = _parse_ceiling(cfg.read_text(encoding="utf-8"))
    except OSError:
        return DEFAULT_BENCHMARK_CEILING_USD, "scorecard.py default (config/budget.yml unread)"
    if parsed is _CEILING_KEY_ABSENT:
        return DEFAULT_BENCHMARK_CEILING_USD, "scorecard.py default (config/budget.yml unread)"
    if parsed is None:
        return None, "config/budget.yml (benchmark_per_run_usd_cap unreadable: non-finite or non-positive)"
    return parsed, "config/budget.yml"


def _mean(values: list[float]) -> float:
    return sum(values) / len(values)


def _fmt(value, spec: str) -> str:
    return "null" if value is None else format(value, spec)


def _tokens(rec: dict, field: str):
    return rec.get(field)


def _total_tokens(rec: dict):
    if "input_tokens" in rec and "output_tokens" in rec:
        return rec["input_tokens"] + rec["output_tokens"]
    return None


def paired(trials: list[dict], treatment: str) -> list[tuple[dict, dict]]:
    controls = {
        (r["case_id"], r["trial"]): r for r in trials if r["strategy"] == CONTROL
    }
    out: list[tuple[dict, dict]] = []
    for rec in trials:
        if rec["strategy"] != treatment:
            continue
        ctl = controls.get((rec["case_id"], rec["trial"]))
        if ctl is not None:
            out.append((ctl, rec))
    out.sort(key=lambda pair: (pair[1]["case_id"], pair[1]["trial"]))
    return out


def deltas(pairs: list[tuple[dict, dict]]) -> dict:
    n = len(pairs)
    d = {"pairs": n}
    if n == 0:
        return d
    d["success_pp"] = 100.0 * (_mean([t["accepted"] for _, t in pairs])
                               - _mean([c["accepted"] for c, _ in pairs]))
    d["first_pass_pp"] = 100.0 * (_mean([t["first_pass_accepted"] for _, t in pairs])
                                  - _mean([c["first_pass_accepted"] for c, _ in pairs]))
    d["rework_pp"] = 100.0 * (_mean([t["rework_required"] for _, t in pairs])
                              - _mean([c["rework_required"] for c, _ in pairs]))
    d["wall_s"] = _mean([t["wall_time_seconds"] - c["wall_time_seconds"] for c, t in pairs])
    d["calls"] = _mean([t["model_calls"] - c["model_calls"] for c, t in pairs])
    for field, label in (("input_tokens", "in_tok"), ("output_tokens", "out_tok")):
        if all(field in c and field in t for c, t in pairs):
            d[label] = _mean([t[field] - c[field] for c, t in pairs])
        else:
            d[label] = None
    d["q10k_control"], d["q10k_treatment"] = _quality_per_10k(pairs)
    d["qmin_control"], d["qmin_treatment"] = _quality_per_minute(pairs)
    return d


def _quality_per_10k(pairs):
    ok = all(
        "quality_score" in c and "quality_score" in t
        and _total_tokens(c) not in (None, 0) and _total_tokens(t) not in (None, 0)
        for c, t in pairs
    )
    if not ok:
        return None, None
    ctl = _mean([c["quality_score"] * 10000.0 / _total_tokens(c) for c, _ in pairs])
    trt = _mean([t["quality_score"] * 10000.0 / _total_tokens(t) for _, t in pairs])
    return ctl, trt


def _quality_per_minute(pairs):
    ok = all(
        "quality_score" in c and "quality_score" in t
        and c["wall_time_seconds"] > 0 and t["wall_time_seconds"] > 0
        for c, t in pairs
    )
    if not ok:
        return None, None
    ctl = _mean([c["quality_score"] / (c["wall_time_seconds"] / 60.0) for c, _ in pairs])
    trt = _mean([t["quality_score"] / (t["wall_time_seconds"] / 60.0) for _, t in pairs])
    return ctl, trt


def _delta_lines(d: dict, indent: str = "") -> list[str]:
    if d["pairs"] == 0:
        return [f"{indent}pairs: 0 (no paired control trials)"]
    return [
        f"{indent}pairs:                 {d['pairs']}",
        f"{indent}success_pp_delta:      {_fmt(d['success_pp'], '+.1f')}",
        f"{indent}first_pass_pp_delta:   {_fmt(d['first_pass_pp'], '+.1f')}",
        f"{indent}rework_rate_pp_delta:  {_fmt(d['rework_pp'], '+.1f')}",
        f"{indent}wall_time_s_delta:     {_fmt(d['wall_s'], '+.3f')}",
        f"{indent}model_calls_delta:     {_fmt(d['calls'], '+.3f')}",
        f"{indent}input_tokens_delta:    {_fmt(d['in_tok'], '+.1f')}",
        f"{indent}output_tokens_delta:   {_fmt(d['out_tok'], '+.1f')}",
        f"{indent}quality_per_10k_tokens: control={_fmt(d['q10k_control'], '.2f')} "
        f"treatment={_fmt(d['q10k_treatment'], '.2f')}",
        f"{indent}quality_per_minute:    control={_fmt(d['qmin_control'], '.2f')} "
        f"treatment={_fmt(d['qmin_treatment'], '.2f')}",
    ]


def route_block(trials: list[dict]) -> list[str]:
    lines = ["== route-correctness (separate axis; an outcome win does not imply a correct route) =="]
    present = [s for s in STRATEGY_REPORT_ORDER if any(r["strategy"] == s for r in trials)]
    for strategy in present:
        recs = [r for r in trials if r["strategy"] == strategy]
        lanes = 0
        correct = 0
        incorrect_trials = 0
        per_role: dict[str, dict[tuple, int]] = {}
        for rec in recs:
            trial_bad = False
            for route in rec["route_evidence"]:
                lanes += 1
                exp_model = route.get("expected_model")
                if exp_model is None:
                    graded = None
                else:
                    graded = (route["model"] == exp_model and route["effort"] == route["expected_effort"])
                if graded is True:
                    correct += 1
                elif graded is False:
                    trial_bad = True
                combo = (
                    route["role"], route["model"], route["effort"],
                    exp_model if exp_model is not None else "-",
                    route["expected_effort"],
                    "OK" if graded is True else ("MISMATCH" if graded is False else "model=unchecked"),
                )
                per_role.setdefault(route["role"], {})
                per_role[route["role"]][combo] = per_role[route["role"]].get(combo, 0) + 1
            if trial_bad:
                incorrect_trials += 1
        graded_lanes = sum(
            1 for r in recs for rt in r["route_evidence"] if rt.get("expected_model") is not None
        )
        lines.append(f"strategy={strategy}")
        lines.append(
            f"  lanes: {lanes}  graded_lanes: {graded_lanes}  route-correct: {correct}  "
            f"route-incorrect: {graded_lanes - correct}"
        )
        lines.append(f"  trials with >=1 route-incorrect lane: {incorrect_trials} of {len(recs)}")
        for role in sorted(per_role):
            for combo in sorted(per_role[role]):
                role_, obs_m, obs_e, exp_m, exp_e, status = combo
                count = per_role[role][combo]
                lines.append(
                    f"  role={role_:<14} observed={obs_m}/{obs_e}  expected={exp_m}/{exp_e}  "
                    f"status={status}  (x{count})"
                )
    return lines


def render(trials: list[dict], source: str) -> str:
    counts = {s: sum(1 for r in trials if r["strategy"] == s) for s in STRATEGIES}
    cases = sorted({r["case_id"] for r in trials})
    # FIX (security HIGH, round 3): integrity_ok is REQUIRED to contribute. `is True` --
    # not `is not False` -- so a record MISSING the field, or carrying any non-true value,
    # is excluded from every delta AND from the route table (route_block(scored) below).
    # This is the fail-CLOSED counterpart of the earlier fail-open `is not False`.
    scored = [r for r in trials if r.get("integrity_ok") is True]
    excluded = [r for r in trials if r.get("integrity_ok") is not True]
    integrity_failed = [r for r in trials if r.get("integrity_ok") is False]
    missing_or_other = len(excluded) - len(integrity_failed)
    # FIX (security MEDIUM): the per-run dollar ceiling is only checkable after the fact if
    # every SCORED trial carries its own cost. config/budget.yml is the source of the
    # ceiling; nothing here BLOCKS an over-ceiling run (docs/BUDGET.md).
    ceiling, ceiling_src = _read_ceiling()
    scored_costs = [r.get("cost_usd") for r in scored]
    if ceiling is None:
        # FIX (security LOW): a non-finite / non-positive / unparseable ceiling can never
        # produce a WITHIN verdict. Say so plainly instead.
        cost_line = (
            f"run cost: ceiling unreadable [{ceiling_src}] -- not checkable"
        )
    elif scored and all(c is not None for c in scored_costs):
        total_cost = sum(scored_costs)
        verdict = "WITHIN" if total_cost <= ceiling else "OVER"
        cost_line = (
            f"run cost ${total_cost:.2f} vs ceiling ${ceiling:.2f} "
            f"[{ceiling_src}]: {verdict}"
        )
    else:
        n_missing = sum(1 for c in scored_costs if c is None)
        cost_line = (
            f"run cost: unknown (cost_usd missing on {n_missing} scored trial(s)) "
            f"-- ceiling ${ceiling:.2f} [{ceiling_src}] not checkable"
        )
    out: list[str] = []
    out.append("sefi-agents benchmark scorecard")
    out.append(f"source: {source}")
    out.append(f"schema_version: {SCHEMA_VERSION}")
    out.append(
        f"trials: {len(trials)}  (control={counts[CONTROL]}, "
        f"sefi-chain={counts['sefi-chain']}, sefi-chain-sequential={counts['sefi-chain-sequential']})"
    )
    out.append(f"scored trials (integrity_ok is true): {len(scored)}")
    out.append(
        f"excluded (integrity_ok not true): {len(excluded)} "
        f"(integrity_ok false: {len(integrity_failed)}, missing/other: {missing_or_other})"
    )
    out.append(cost_line)
    out.append("")
    out.append("== aggregate deltas (treatment minus control, paired on case_id+trial) ==")
    for treatment in TREATMENTS:
        out.append("")
        out.append(f"-- {treatment} vs control --")
        out.extend(_delta_lines(deltas(paired(scored, treatment)), indent="  "))
    out.append("")
    out.append("== per-case deltas ==")
    for case_id in cases:
        subset = [r for r in scored if r["case_id"] == case_id]
        out.append("")
        out.append(f"-- case: {case_id} --")
        for treatment in TREATMENTS:
            d = deltas(paired(subset, treatment))
            if d["pairs"] == 0:
                out.append(f"  {treatment} vs control: pairs=0")
                continue
            out.append(
                f"  {treatment} vs control: "
                f"success_pp={_fmt(d['success_pp'], '+.1f')} "
                f"first_pass_pp={_fmt(d['first_pass_pp'], '+.1f')} "
                f"rework_pp={_fmt(d['rework_pp'], '+.1f')} "
                f"wall_s={_fmt(d['wall_s'], '+.3f')} "
                f"calls={_fmt(d['calls'], '+.3f')} "
                f"in_tok={_fmt(d['in_tok'], '+.1f')} "
                f"out_tok={_fmt(d['out_tok'], '+.1f')}"
            )
    out.append("")
    # FIX (security HIGH / QA): the route table is built from `scored` only -- a trial that
    # is not integrity-verified contributes to NOTHING, route axis included.
    out.extend(route_block(scored))
    out.append("")
    out.append(
        "note: a result showing the chain LOSING on some task classes is an accepted "
        "outcome, not a harness failure."
    )
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="scorecard.py",
        description=(
            "Deterministic scorer for the blinded paired A/B benchmark harness. Reads a "
            "JSONL trial-record file and prints paired treatment-minus-control deltas plus "
            "a separate route-correctness table. Standard library only; makes no model "
            "call, no dispatch, no network request, and writes nothing."
        ),
    )
    parser.add_argument("trials", type=Path, help="JSONL file, one trial record per line")
    args = parser.parse_args(argv)
    try:
        trials = load_trials(args.trials)
    except BenchmarkError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    # FIX G (security MEDIUM 6): print only the basename of the trials file, never the
    # absolute invocation path -- run artifacts must have a leak boundary.
    text = render(trials, args.trials.name)
    # Write raw UTF-8 with LF endings so the output is byte-identical on every platform
    # (Windows text-mode stdout would otherwise rewrite \n to \r\n and break the
    # determinism fixture check).
    buffer = getattr(sys.stdout, "buffer", None)
    if buffer is not None:
        buffer.write(text.encode("utf-8"))
        buffer.flush()
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
