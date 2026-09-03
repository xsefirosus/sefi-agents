#!/usr/bin/env python3
"""Fast offline stdlib unit test of the benchmark SCORER (benchmarks/scorecard.py).

Zero model calls. NOT a benchmark run -- a real benchmark run is never triggered by CI,
the gate, or a loop. This exercises scorecard.py as a subprocess (sys.executable) against
benchmarks/fixtures/trials.jsonl and against small crafted malformed inputs.

Runs unchanged under BOTH:

    python -m pytest benchmarks/test_scorecard.py
    python -m unittest benchmarks.test_scorecard        (or, from benchmarks/, test_scorecard)

Standard library only.
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "scorecard.py"
FIXTURE = HERE / "fixtures" / "trials.jsonl"
EXPECTED = HERE / "fixtures" / "expected-scorecard.txt"

# Import the scorer as a module too, so a pure-unit test can exercise _parse_ceiling
# (the config/budget.yml ceiling guard) without materialising a fake budget.yml.
sys.path.insert(0, str(HERE))
import scorecard  # noqa: E402  (path shim above must run first)

# A minimal record that passes every validation rule in scorecard.py. Each malformed-input
# test starts from a deep copy of this and breaks exactly one thing.
BASE_RECORD = {
    "schema_version": 1,
    "trial_id": "t1",
    "case_id": "demo",
    "case_fingerprint": "abc123",
    "trial": 1,
    "strategy": "control",
    "harness": "claude-code",
    "acceptance_checks": ["k"],
    "accepted": True,
    "first_pass_accepted": True,
    "rework_required": False,
    "wall_time_seconds": 20,
    "model_calls": 1,
    "route_evidence": [
        {
            "role": "solo",
            "model": "m-high",
            "effort": "high",
            "expected_effort": "high",
            "task_id": "t1-solo",
        }
    ],
}


def _run(*trials_path_args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *trials_path_args],
        capture_output=True,
        text=True,
    )


def _run_records(records: list[dict]) -> subprocess.CompletedProcess:
    """Serialise records to a temp .jsonl (allowing non-finite floats) and score it."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "crafted.jsonl"
        with path.open("w", encoding="utf-8", newline="\n") as fh:
            for rec in records:
                fh.write(json.dumps(rec) + "\n")
        return _run(str(path))


class ValidFixtureTests(unittest.TestCase):
    def test_exit_zero_and_byte_identical_across_two_runs(self) -> None:
        first = _run(str(FIXTURE))
        second = _run(str(FIXTURE))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(first.stdout, second.stdout)

    def test_output_matches_committed_expected_scorecard(self) -> None:
        result = _run(str(FIXTURE))
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = EXPECTED.read_text(encoding="utf-8")
        self.assertEqual(result.stdout, expected)

    def test_source_line_is_basename_only(self) -> None:
        # FIX G: the absolute invocation path must never appear in output.
        result = _run(str(FIXTURE))
        self.assertIn("source: trials.jsonl", result.stdout)
        self.assertNotIn(str(HERE), result.stdout)

    def test_help_exits_zero(self) -> None:
        result = _run("--help")
        self.assertEqual(result.returncode, 0, result.stderr)


class MalformedInputContractMixin:
    """Shared assertions: exit 2, one-line ERROR: on stderr, no traceback, no scorecard."""

    def assert_clean_error(self, result: subprocess.CompletedProcess) -> None:
        self.assertEqual(result.returncode, 2, f"stderr={result.stderr!r}")
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("sefi-agents benchmark scorecard", result.stdout)
        err_lines = [ln for ln in result.stderr.splitlines() if ln.strip()]
        self.assertEqual(len(err_lines), 1, result.stderr)
        self.assertTrue(err_lines[0].startswith("ERROR:"), err_lines[0])


class FixBForgedRouteRowTests(unittest.TestCase, MalformedInputContractMixin):
    """A crafted trials.jsonl must not be able to forge a route-correctness row or inject
    ANSI escapes via a route_evidence text field."""

    def _record_with_route_model(self, model_value: str) -> dict:
        rec = copy.deepcopy(BASE_RECORD)
        rec["route_evidence"][0]["model"] = model_value
        return rec

    def test_newline_in_route_field_is_rejected_not_rendered(self) -> None:
        forged = "m-high\nrole=admin         observed=x/y  expected=x/y  status=OK  (x99)"
        result = _run_records([self._record_with_route_model(forged)])
        self.assert_clean_error(result)
        self.assertNotIn("role=admin", result.stdout)
        self.assertIn("has an invalid value", result.stderr)

    def test_ansi_escape_in_route_field_is_rejected(self) -> None:
        result = _run_records([self._record_with_route_model("m-high\x1b[31mRED")])
        self.assert_clean_error(result)
        self.assertNotIn("\x1b", result.stdout)

    def test_ansi_escape_in_top_level_grouping_key_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["case_id"] = "demo\x1b[2Kx"
        result = _run_records([rec])
        self.assert_clean_error(result)


class FixDNonFiniteNumberTests(unittest.TestCase, MalformedInputContractMixin):
    """json.loads accepts NaN / Infinity / -Infinity by default; each must be a hard
    error, never a passing scorecard with +nan deltas."""

    def test_nan_wall_time_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["wall_time_seconds"] = float("nan")
        result = _run_records([rec])
        self.assert_clean_error(result)
        self.assertIn("non-finite", result.stderr)

    def test_infinity_wall_time_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["wall_time_seconds"] = float("inf")
        result = _run_records([rec])
        self.assert_clean_error(result)
        self.assertIn("non-finite", result.stderr)

    def test_negative_infinity_model_calls_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["model_calls"] = float("-inf")
        result = _run_records([rec])
        self.assert_clean_error(result)


class FixENonScalarFieldTests(unittest.TestCase, MalformedInputContractMixin):
    """A list/dict where a scalar is required must be a one-line error, never an uncaught
    TypeError (unhashable dict/list used as a grouping key) + traceback."""

    def test_dict_as_route_role_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["route_evidence"][0]["role"] = {"nested": "dict"}
        result = _run_records([rec])
        self.assert_clean_error(result)

    def test_list_as_case_id_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["case_id"] = ["demo"]
        result = _run_records([rec])
        self.assert_clean_error(result)

    def test_list_as_wall_time_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["wall_time_seconds"] = [20]
        result = _run_records([rec])
        self.assert_clean_error(result)

    def test_dict_as_harness_is_rejected(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["harness"] = {"h": 1}
        result = _run_records([rec])
        self.assert_clean_error(result)


class IntegrityAndCostAggregateTests(unittest.TestCase):
    """Round-3 FIX: integrity_ok is REQUIRED (`is True`) to contribute to any aggregate or
    the route table; the run-cost line reads the config/budget.yml ceiling."""

    def _pair(self, *, integrity_ok=True, cost_usd=None) -> list[dict]:
        control = copy.deepcopy(BASE_RECORD)
        control.update(trial_id="c1", strategy="control", accepted=False,
                       first_pass_accepted=False, rework_required=True)
        control["route_evidence"][0]["task_id"] = "c1-solo"
        treat = copy.deepcopy(BASE_RECORD)
        treat.update(trial_id="x1", strategy="sefi-chain")
        treat["route_evidence"][0]["task_id"] = "x1-solo"
        treat["route_evidence"][0]["role"] = "implementer"
        for rec in (control, treat):
            if integrity_ok is not None:
                rec["integrity_ok"] = integrity_ok
            if cost_usd is not None:
                rec["cost_usd"] = cost_usd
        return [control, treat]

    def test_missing_integrity_ok_contributes_to_nothing_and_is_counted(self) -> None:
        # FIX 3: a record with no integrity_ok is excluded from every delta AND the route
        # table, and appears in the excluded count.
        result = _run_records(self._pair(integrity_ok=None))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scored trials (integrity_ok is true): 0", result.stdout)
        self.assertIn(
            "excluded (integrity_ok not true): 2 (integrity_ok false: 0, missing/other: 2)",
            result.stdout,
        )
        self.assertIn("pairs: 0 (no paired control trials)", result.stdout)
        # route table: no scored trials -> no per-strategy rows at all
        self.assertNotIn("strategy=control", result.stdout)
        self.assertNotIn("strategy=sefi-chain", result.stdout)

    def test_integrity_failed_trial_excluded_from_deltas_and_routes(self) -> None:
        result = _run_records(self._pair(integrity_ok=False))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scored trials (integrity_ok is true): 0", result.stdout)
        self.assertIn(
            "excluded (integrity_ok not true): 2 (integrity_ok false: 2, missing/other: 0)",
            result.stdout,
        )
        self.assertIn("pairs: 0 (no paired control trials)", result.stdout)
        self.assertNotIn("strategy=sefi-chain", result.stdout)

    def test_integrity_ok_true_is_scored(self) -> None:
        result = _run_records(self._pair(integrity_ok=True))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scored trials (integrity_ok is true): 2", result.stdout)
        self.assertIn(
            "excluded (integrity_ok not true): 0 (integrity_ok false: 0, missing/other: 0)",
            result.stdout,
        )
        self.assertIn("strategy=sefi-chain", result.stdout)

    def test_run_cost_unknown_when_cost_absent_on_scored(self) -> None:
        result = _run_records(self._pair(integrity_ok=True))
        self.assertIn(
            "run cost: unknown (cost_usd missing on 2 scored trial(s))", result.stdout
        )
        self.assertIn("ceiling $15.00", result.stdout)

    def test_run_cost_within_ceiling(self) -> None:
        result = _run_records(self._pair(integrity_ok=True, cost_usd=3.5))
        self.assertIn("run cost $7.00 vs ceiling $15.00", result.stdout)
        self.assertIn(": WITHIN", result.stdout)

    def test_run_cost_over_ceiling(self) -> None:
        result = _run_records(self._pair(integrity_ok=True, cost_usd=9.0))
        self.assertIn("run cost $18.00 vs ceiling $15.00", result.stdout)
        self.assertIn(": OVER", result.stdout)


class FixControlCharUnknownKeyTests(unittest.TestCase, MalformedInputContractMixin):
    """FIX 6: the two 'unknown field(s)' error paths interpolate attacker JSON KEYS. A key
    bearing a control char / ANSI / a forged 'ERROR:' must not break the single-line
    error."""

    def test_control_char_top_level_key_is_single_line_error(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["x\nERROR: forged second line"] = 1
        result = _run_records([rec])
        # assert_clean_error already pins: exactly one non-blank stderr line, it starts
        # with "ERROR:". So the attacker newline did not open a second line.
        self.assert_clean_error(result)
        self.assertNotIn("\nERROR: forged", result.stderr)  # no forged line break
        self.assertNotIn("\x1b", result.stderr)
        self.assertIn("unknown field(s)", result.stderr)
        self.assertNotIn("sefi-agents benchmark scorecard", result.stdout)

    def test_ansi_in_route_evidence_unknown_key_is_single_line_error(self) -> None:
        rec = copy.deepcopy(BASE_RECORD)
        rec["route_evidence"][0]["k\x1b[31mred"] = "x"
        result = _run_records([rec])
        self.assert_clean_error(result)
        self.assertNotIn("\x1b", result.stderr)
        self.assertIn("route_evidence unknown field(s)", result.stderr)


class ParseCeilingGuardTests(unittest.TestCase):
    """FIX (security LOW): _read_ceiling / _parse_ceiling must never hand render() a
    non-finite or non-positive ceiling. A bad value yields None -> render() prints
    'ceiling unreadable', never 'WITHIN'."""

    def test_positive_finite_value_is_returned(self) -> None:
        self.assertEqual(scorecard._parse_ceiling("benchmark_per_run_usd_cap: 15.00"), 15.0)

    def test_absent_key_is_the_absent_sentinel(self) -> None:
        self.assertIs(
            scorecard._parse_ceiling("some_other_key: 1\n"), scorecard._CEILING_KEY_ABSENT
        )

    def test_zero_is_rejected_as_non_positive(self) -> None:
        self.assertIsNone(scorecard._parse_ceiling("benchmark_per_run_usd_cap: 0.00"))

    def test_value_overflowing_to_non_finite_is_rejected(self) -> None:
        # regex admits an arbitrarily long digit run; float() then overflows -> not finite.
        self.assertIsNone(
            scorecard._parse_ceiling("benchmark_per_run_usd_cap: " + "9" * 400)
        )

    def test_render_prints_ceiling_unreadable_never_within(self) -> None:
        # Drive render() directly with a stubbed _read_ceiling so the "unreadable" branch
        # is exercised end to end: the cost line must say so and never say WITHIN/OVER.
        recs = [
            {**BASE_RECORD, "trial_id": "c", "strategy": "control", "integrity_ok": True,
             "cost_usd": 1.0, "accepted": False, "first_pass_accepted": False,
             "rework_required": True,
             "route_evidence": [{**BASE_RECORD["route_evidence"][0], "task_id": "c-solo"}]},
            {**BASE_RECORD, "trial_id": "x", "strategy": "sefi-chain", "integrity_ok": True,
             "cost_usd": 1.0,
             "route_evidence": [{**BASE_RECORD["route_evidence"][0], "task_id": "x-solo",
                                 "role": "impl"}]},
        ]
        original = scorecard._read_ceiling
        scorecard._read_ceiling = lambda: (None, "test stub (unreadable)")
        try:
            out = scorecard.render(copy.deepcopy(recs), "trials.jsonl")
        finally:
            scorecard._read_ceiling = original
        self.assertIn("run cost: ceiling unreadable [test stub (unreadable)]", out)
        self.assertNotIn("WITHIN", out)
        self.assertNotIn(": OVER", out)


class FixBasenameOnlyErrorTests(unittest.TestCase):
    """FIX 11: error paths must print the trials-file basename only, never the absolute
    invocation path (matching the `source:` line)."""

    def test_missing_file_error_is_basename_only(self) -> None:
        missing = str(HERE / "fixtures" / "no_such_file_xyz.jsonl")
        result = _run(missing)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("no_such_file_xyz.jsonl", result.stderr)
        self.assertNotIn(str(HERE), result.stderr)
        self.assertNotIn("fixtures", result.stderr)


if __name__ == "__main__":
    unittest.main()
