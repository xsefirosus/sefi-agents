#!/usr/bin/env python3
"""Fast offline stdlib unit test of the out-of-process benchmark RUNNER.

Zero model calls. NOT a benchmark run -- a real benchmark run is never triggered by CI,
the gate, or a loop. This exercises benchmarks/runner/sandbox.py and
benchmarks/runner/snapshot.py directly.

Runs unchanged under BOTH:

    python -m pytest benchmarks/test_runner.py
    python -m unittest benchmarks.test_runner        (or, from benchmarks/, test_runner)

Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    # Under pytest's default import mode only benchmarks/ lands on sys.path, so the
    # ``benchmarks.runner`` package would not import. Mirrors nothing in test_scorecard.py
    # (which shells out instead); this suite imports the runner modules under test.
    sys.path.insert(0, str(REPO_ROOT))

from benchmarks.runner.arms import ArmResult, run_arm  # noqa: E402
from benchmarks.runner.integrity import verify  # noqa: E402
from benchmarks.runner.record import build_record  # noqa: E402
from benchmarks.runner.route import RouteResult, capture_route  # noqa: E402
from benchmarks.runner.sandbox import resolve_git, resolve_python, sandbox  # noqa: E402
from benchmarks.runner.snapshot import diff, snapshot  # noqa: E402

SCORECARD = REPO_ROOT / "benchmarks" / "scorecard.py"

# A tracked file under benchmarks/ used for the check-attr assertion. check_sh-strict-mode.sh
# exists on this branch (benchmarks/cases/), so no substitution was needed.
CHECK_ATTR_TARGET = "benchmarks/cases/check_sh-strict-mode.sh"

FIXTURES = REPO_ROOT / "benchmarks" / "runner" / "fixtures"
MOCK_ARM = FIXTURES / "mock_arm.py"
MOCK_ARM_SLOW = FIXTURES / "mock_arm_slow.py"
MOCK_ARM_TAMPER = FIXTURES / "mock_arm_tamper.py"
MOCK_ARM_FORGE = FIXTURES / "mock_arm_forge.py"
MOCK_ARM_WRONGSESSION = FIXTURES / "mock_arm_wrongsession.py"
CHECK_ROUTE_STUB = FIXTURES / "check-route-stub.sh"
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
SH_STRICT_PROMPT = (
    REPO_ROOT / "benchmarks" / "prompts" / "sh-strict-mode.md"
).read_text(encoding="utf-8")
SH_STRICT_CHECK = REPO_ROOT / "benchmarks" / "cases" / "check_sh-strict-mode.sh"


def _resolve_tool(names: tuple[str, ...]) -> str | None:
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    return None


BASH = _resolve_tool(("bash.exe", "bash"))


class _PinnedTempdirMixin:
    """FIX F: pin every ``tempfile.mkdtemp`` a test triggers (sandbox.py, arms.py, and any
    ``tempfile.TemporaryDirectory()`` in the test body) to a PRIVATE per-test dir, then
    assert scratch leaks only against THAT dir. A concurrent runner / qa process sharing
    the real ``%TEMP%`` can no longer redden the leak assertions with its own
    ``sefi-bench-*`` / ``sefi-arm-*`` dirs. ``tempfile`` caches ``gettempdir()``, so the
    module-level cache is swapped too and restored in ``tearDown``.
    """

    def setUp(self) -> None:
        super().setUp()
        self._pinned_tmp = tempfile.mkdtemp(prefix="sefi-runnertest-")
        self._saved_tmp_env = {k: os.environ.get(k) for k in ("TMPDIR", "TEMP", "TMP")}
        self._saved_tempdir = tempfile.tempdir
        for key in ("TMPDIR", "TEMP", "TMP"):
            os.environ[key] = self._pinned_tmp
        tempfile.tempdir = self._pinned_tmp

    def tearDown(self) -> None:
        tempfile.tempdir = self._saved_tempdir
        for key, value in self._saved_tmp_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        shutil.rmtree(self._pinned_tmp, ignore_errors=True)
        super().tearDown()

    def _assert_no_scratch_leak(self, *, prefixes: tuple[str, ...] = ("sefi-bench-", "sefi-arm-")) -> None:
        leaked = sorted(
            p.name for p in Path(self._pinned_tmp).iterdir() if p.name.startswith(prefixes)
        )
        self.assertEqual(leaked, [], f"scratch dirs leaked this run: {leaked}")


class ResolveTests(unittest.TestCase):
    def test_resolve_git_is_absolute_executable(self) -> None:
        path = resolve_git()
        self.assertTrue(Path(path).is_absolute())
        self.assertTrue(Path(path).is_file())
        proc = subprocess.run(
            [path, "--version"], capture_output=True, text=True, check=True
        )
        self.assertIn("git version", proc.stdout)

    def test_resolve_python_runs(self) -> None:
        path = resolve_python()
        proc = subprocess.run(
            [path, "--version"], capture_output=True, text=True, check=True
        )
        self.assertTrue(proc.stdout.strip().startswith("Python"))


class SandboxTests(unittest.TestCase):
    def test_clone_has_own_object_store(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as repo:
            self.assertTrue((repo / ".git").is_dir(), ".git must be a real directory")
            self.assertFalse(
                (repo / ".git" / "objects" / "info" / "alternates").exists(),
                "clone must have its own object store (no alternates)",
            )

    def test_origin_remote_and_origin_url_are_stripped(self) -> None:
        # FIX A: the clone must not disclose the operator's absolute origin path to the
        # arm. ``git remote`` is empty and ``.git/config`` names no ``file://`` url.
        git = resolve_git()
        with sandbox(REPO_ROOT, "HEAD") as repo:
            proc = subprocess.run(
                [git, "-C", str(repo), "remote"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(proc.stdout.strip(), "", "origin remote must be removed")
            config_text = (repo / ".git" / "config").read_text(encoding="utf-8")
            self.assertNotIn("file://", config_text)
            self.assertNotIn("benchmark-runner", config_text)

    def test_checkout_line_endings_unset(self) -> None:
        git = resolve_git()
        with sandbox(REPO_ROOT, "HEAD") as repo:
            proc = subprocess.run(
                [git, "-C", str(repo), "check-attr", "text", "--", CHECK_ATTR_TARGET],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(proc.stdout.strip(), f"{CHECK_ATTR_TARGET}: text: unset")

    def test_scratch_removed_after_block(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as repo:
            scratch = repo.parent
            self.assertTrue(scratch.is_dir())
        self.assertFalse(scratch.exists(), "scratch dir must be gone after the with block")

    def test_teardown_runs_on_error(self) -> None:
        captured: dict[str, Path] = {}

        class Boom(RuntimeError):
            pass

        with self.assertRaises(Boom):
            with sandbox(REPO_ROOT, "HEAD") as repo:
                captured["scratch"] = repo.parent
                raise Boom
        self.assertFalse(
            captured["scratch"].exists(), "teardown must run even on error/timeout"
        )


class SnapshotTests(unittest.TestCase):
    def _build_tree(self, root: Path) -> None:
        (root / "keep.txt").write_bytes(b"original\n")
        (root / "pkg").mkdir()
        (root / "pkg" / "mod.py").write_bytes(b"print(1)\n")
        gitdir = root / ".git"
        gitdir.mkdir()
        (gitdir / "HEAD").write_bytes(b"ref: refs/heads/main\n")

    def test_excludes_git_and_uses_posix_relpaths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._build_tree(root)
            manifest = snapshot(root)
        self.assertEqual(sorted(manifest), ["keep.txt", "pkg/mod.py"])
        self.assertNotIn(".git/HEAD", manifest)

    def test_diff_reports_mutation_and_addition_outside_allowlist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._build_tree(root)
            before = snapshot(root)
            (root / "keep.txt").write_bytes(b"MUTATED\n")
            (root / "pkg" / "new.py").write_bytes(b"print(2)\n")
            after = snapshot(root)

        self.assertEqual(
            diff(before, after, ["pkg/mod.py"]),
            ["keep.txt", "pkg/new.py"],
        )
        self.assertEqual(diff(before, after, ["keep.txt", "pkg"]), [])

    def test_diff_reports_removal_outside_allowlist(self) -> None:
        before = {"a.txt": "h1", "b.txt": "h2"}
        after = {"a.txt": "h1"}
        self.assertEqual(diff(before, after, []), ["b.txt"])
        self.assertEqual(diff(before, after, ["b.txt"]), [])

    def test_two_independent_clones_yield_identical_manifest(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as repo_a:
            manifest_a = snapshot(repo_a)
        with sandbox(REPO_ROOT, "HEAD") as repo_b:
            manifest_b = snapshot(repo_b)
        self.assertEqual(manifest_a, manifest_b)
        # Byte-identical serialization, not just equal dicts.
        import json

        self.assertEqual(
            json.dumps(manifest_a, sort_keys=True),
            json.dumps(manifest_b, sort_keys=True),
        )


class ArmsTests(_PinnedTempdirMixin, unittest.TestCase):
    """Step 4: benchmarks/runner/arms.run_arm -- all via the --mock-arm seam."""

    def test_raw_log_has_no_operator_path(self) -> None:
        # FIX C: the copied raw log must not embed the operator's home dir via cmd[1:]
        # (the arm-scratch prompt path lives under %TEMP%, itself under the home dir).
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            result = run_arm(
                "control", "claude-code", SH_STRICT_PROMPT, repo,
                timeout_s=5, mock_arm=MOCK_ARM, results_dir=Path(out),
            )
            text = Path(result.raw_log_path).read_text(encoding="utf-8")
        self.assertNotIn(str(Path.home()), text)
        self.assertNotIn("MARYRO", text)
        self.assertNotIn("Mary Rose", text)

    def test_timed_out_arm_leaves_no_arm_scratch(self) -> None:
        # FIX D: arm-scratch teardown is the shared read-only-retry _rmtree, not a
        # swallowing ignore_errors=True. A 0.1s-timeout arm still leaves zero sefi-arm-*
        # dirs. Scoped to this test's pinned tempdir (FIX F).
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            run_arm(
                "control", "claude-code", SH_STRICT_PROMPT, repo,
                timeout_s=0.1, mock_arm=MOCK_ARM_SLOW, results_dir=Path(out),
            )
        self._assert_no_scratch_leak(prefixes=("sefi-arm-",))

    def test_mock_arm_completes_case_and_reports_runner_observed_facts(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            result = run_arm(
                "control",
                "claude-code",
                SH_STRICT_PROMPT,
                repo,
                timeout_s=5,
                mock_arm=MOCK_ARM,
                results_dir=Path(out),
            )
            self.assertIsInstance(result, ArmResult)
            self.assertEqual(result.exit_code, 0)
            self.assertIsInstance(result.wall_time_s, float)
            self.assertGreaterEqual(result.wall_time_s, 0.0)
            # session id captured BY THE RUNNER from the invocation, not from arm stdout.
            self.assertIsNotNone(result.session_record_ref)
            # raw log is a human artifact under the results dir.
            self.assertTrue(Path(result.raw_log_path).is_file())
            self.assertTrue(
                Path(result.raw_log_path).parent.samefile(out),
                "raw log must live under the runner-owned results dir, outside the sandbox",
            )
            # the sandbox target now satisfies the case's acceptance check.
            self.assertIsNotNone(BASH, "bash must be on PATH for this suite")
            proc = subprocess.run(
                [BASH, str(SH_STRICT_CHECK), repo.as_posix()],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_honest_arm_session_ref_is_a_uuid_the_runner_generated(self) -> None:
        # FIX 2: mock_arm.py echoes SEFI_ARM_SESSION_ID verbatim -> run_arm returns it.
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            result = run_arm(
                "control", "claude-code", SH_STRICT_PROMPT, repo,
                timeout_s=5, mock_arm=MOCK_ARM, results_dir=Path(out),
            )
        self.assertIsNotNone(result.session_record_ref)
        self.assertRegex(result.session_record_ref, UUID_RE)

    def test_mismatched_session_echo_yields_none(self) -> None:
        # FIX 2: an arm that echoes a DIFFERENT lowercase-UUID does NOT get to pick the
        # session ref -- run_arm compares the echo to the id it generated and returns None.
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            result = run_arm(
                "control", "claude-code", SH_STRICT_PROMPT, repo,
                timeout_s=5, mock_arm=MOCK_ARM_WRONGSESSION, results_dir=Path(out),
            )
        self.assertIsNone(result.session_record_ref)

    def test_timeout_is_caught_as_nonfatal_result(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as repo, tempfile.TemporaryDirectory() as out:
            # A 0.1s budget against a mock that sleeps 30s: run_arm must NOT raise.
            result = run_arm(
                "control",
                "claude-code",
                SH_STRICT_PROMPT,
                repo,
                timeout_s=0.1,
                mock_arm=MOCK_ARM_SLOW,
                results_dir=Path(out),
            )
        self.assertNotEqual(result.exit_code, 0)
        self.assertIsInstance(result.wall_time_s, float)
        self.assertGreaterEqual(result.wall_time_s, 0.0)

    def test_sequential_and_parallel_strategies_are_distinct_code_paths(self) -> None:
        # sefi-chain and sefi-chain-sequential are never equated: distinct real-harness
        # invocations. No test touches the real path, so assert the builder directly.
        from benchmarks.runner.arms import _real_command

        parallel = _real_command("sefi-chain", "codex", "PROMPT")
        sequential = _real_command("sefi-chain-sequential", "codex", "PROMPT")
        self.assertNotEqual(parallel, sequential)

    def test_unknown_strategy_is_rejected_at_the_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                run_arm("bogus", "claude-code", "x", tmp, timeout_s=1)


class RouteTests(unittest.TestCase):
    """Step 5: benchmarks/runner/route.capture_route capture / no-capture matrix."""

    def _cap(self, stub: str, ref: str | None = None, harness: str = "codex"):
        return capture_route(
            harness, "high", ref, check_route_cmd=FIXTURES / stub
        )

    def test_not_applicable_exit0_is_captured(self) -> None:
        result = self._cap("check-route-stub.sh", harness="opencode")
        self.assertTrue(result.captured)
        self.assertEqual(result.status, "not-applicable")

    def test_unavailable_exit1_is_captured(self) -> None:
        result = self._cap("check-route-stub-unavailable.sh", harness="claude-code")
        self.assertTrue(result.captured)
        self.assertEqual(result.status, "unavailable")

    def test_exit3_no_interpreter_is_not_captured(self) -> None:
        result = self._cap("check-route-stub-exit3.sh", ref="-")
        self.assertFalse(result.captured)

    def test_invalid_status_exit1_is_not_captured(self) -> None:
        result = self._cap(
            "check-route-stub-invalid.sh",
            ref="00000000-0000-4000-8000-000000000000",
        )
        self.assertFalse(result.captured)
        self.assertEqual(result.status, "invalid")

    def test_non_json_stdout_is_not_captured(self) -> None:
        result = self._cap("check-route-stub-nojson.sh")
        self.assertFalse(result.captured)

    def test_absent_default_script_is_not_captured_without_raising(self) -> None:
        # check-route.sh lives on feat/route-evidence-live, NOT this branch -> fail-closed.
        result = capture_route("claude-code", "high", None, check_route_cmd=None)
        self.assertFalse(result.captured)

    def test_nonexistent_explicit_cmd_is_not_captured(self) -> None:
        result = capture_route(
            "claude-code", "high", None,
            check_route_cmd="/nonexistent/check-route.sh",
        )
        self.assertFalse(result.captured)


_ROUTE_CAPTURED = RouteResult(
    captured=True,
    status="not-applicable",
    reason="stub",
    expected_model=None,
    expected_effort="none",
    observed_model="",
    observed_effort="",
    exit_code=0,
)
_ROUTE_NOT_CAPTURED = _ROUTE_CAPTURED._replace(captured=False, status="invalid", exit_code=1)

# A manifest shaped exactly like snapshot.snapshot() output: {relpath: sha256hex}.
_PRE = {
    "src/a.py": "1111111111111111111111111111111111111111111111111111111111111111",
    "pkg/out/result.txt": "2222222222222222222222222222222222222222222222222222222222222222",
    "README.md": "3333333333333333333333333333333333333333333333333333333333333333",
}
_ALLOWED = ["pkg/out"]
_FINGERPRINT = "cafef00d" * 8  # 64 hex chars -- fits scorecard.py's _TEXT_FIELD_RE.


class IntegrityTests(unittest.TestCase):
    """Step 6a: integrity.verify -- an AND of three mandatory checks, fail-closed."""

    def test_all_three_checks_pass_returns_true(self) -> None:
        post = dict(_PRE)
        self.assertIs(verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_CAPTURED), True)

    def test_change_inside_allowlist_still_passes(self) -> None:
        post = dict(_PRE)
        post["pkg/out/result.txt"] = "9" * 64  # under an allowed_paths entry
        self.assertIs(verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_CAPTURED), True)

    def test_change_outside_allowlist_returns_false(self) -> None:
        post = dict(_PRE)
        post["README.md"] = "9" * 64  # not under any allowed_paths entry
        self.assertIs(verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_CAPTURED), False)

    def test_route_not_captured_returns_false(self) -> None:
        post = dict(_PRE)
        self.assertIs(verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_NOT_CAPTURED), False)

    def test_pre_not_equal_ref_returns_false(self) -> None:
        post = dict(_PRE)
        self.assertIs(
            verify(_PRE, {"other": "x" * 64}, post, _ALLOWED, _ROUTE_CAPTURED), False
        )

    def test_forced_exception_returns_false_not_raised(self) -> None:
        # post_manifest=None -> snapshot.diff raises AttributeError -> caught -> False.
        result = verify(_PRE, dict(_PRE), None, _ALLOWED, _ROUTE_CAPTURED)
        self.assertIs(result, False)

    def test_none_route_result_returns_false_not_raised(self) -> None:
        post = dict(_PRE)
        self.assertIs(verify(_PRE, dict(_PRE), post, _ALLOWED, None), False)

    def test_empty_dict_manifests_fail_by_the_shape_guard_alone(self) -> None:
        # verify({}, {}, {}) is the ONE combination that only the shape guard (check 0)
        # decides: {} == {} passes check 1, snapshot.diff({}, {}, ...) == [] passes
        # check 2, and the route is captured -- so WITHOUT the guard this returns True.
        # With integrity.py's guard line removed, this assertion reddens.
        self.assertIs(verify({}, {}, {}, [], _ROUTE_CAPTURED), False)

    def test_none_manifests_fail_by_guard_or_outer_except(self) -> None:
        # None inputs are failed EITHER by the shape guard (isinstance(None, dict) is
        # False) OR, if the guard were absent, by the outer `except Exception: return
        # False` when snapshot.diff calls None.items(). Both paths end at False; this
        # asserts the outcome, not which line caught it.
        self.assertIs(verify(None, None, None, [], _ROUTE_CAPTURED), False)

    def test_empty_pre_or_post_manifest_returns_false(self) -> None:
        # An empty dict is not a real snapshot -> the guard fails it.
        self.assertIs(verify({}, {}, dict(_PRE), _ALLOWED, _ROUTE_CAPTURED), False)
        self.assertIs(verify(_PRE, dict(_PRE), {}, _ALLOWED, _ROUTE_CAPTURED), False)


class RecordTests(unittest.TestCase):
    """Step 6b: record.build_record -- runner-observed fields only; integrity_ok last."""

    _ACCEPT = {"accepted": True, "first_pass_accepted": True, "rework_required": False}
    _ALLOWED_KEYS = {
        "schema_version", "trial_id", "case_id", "case_fingerprint", "trial", "strategy",
        "harness", "acceptance_checks", "accepted", "first_pass_accepted",
        "rework_required", "wall_time_seconds", "model_calls", "route_evidence",
        "input_tokens", "output_tokens", "quality_score", "quality_score_blinded",
        "integrity_ok", "cost_usd",
    }

    def _build(self, *, trial_id, strategy, integrity_ok_verified, route_result=_ROUTE_CAPTURED):
        return build_record(
            trial_id=trial_id,
            case_id="sh-strict-mode",
            trial=1,
            strategy=strategy,
            harness="claude-code",
            acceptance_checks=["check_sh-strict-mode"],
            acceptance=self._ACCEPT,
            wall_time_seconds=12.5,
            model_calls=1,
            case_fingerprint=_FINGERPRINT,
            route_result=route_result,
            integrity_ok_verified=integrity_ok_verified,
        )

    def test_verified_true_sets_integrity_ok_true(self) -> None:
        rec = self._build(trial_id="ssm-c1", strategy="control", integrity_ok_verified=True)
        self.assertEqual(rec["integrity_ok"], True)

    def test_only_known_scorecard_keys_are_emitted(self) -> None:
        rec = self._build(trial_id="ssm-c1", strategy="control", integrity_ok_verified=True)
        self.assertEqual(set(rec) - self._ALLOWED_KEYS, set())
        lane = rec["route_evidence"][0]
        self.assertEqual(
            set(lane), {"role", "model", "effort", "expected_effort", "task_id"}
        )
        self.assertNotIn("expected_model", lane)  # -> scorecard reports model=unchecked
        self.assertEqual(lane["model"], "not-applicable")  # empty observed -> status word

    def test_verified_false_omits_integrity_ok(self) -> None:
        rec = self._build(trial_id="ssm-c1", strategy="control", integrity_ok_verified=False)
        self.assertNotIn("integrity_ok", rec)

    def test_verified_none_omits_integrity_ok(self) -> None:
        rec = self._build(trial_id="ssm-c1", strategy="control", integrity_ok_verified=None)
        self.assertNotIn("integrity_ok", rec)

    def test_truthy_non_true_omits_integrity_ok(self) -> None:
        # ONLY an explicit True writes the key -- a truthy 1 must not.
        rec = self._build(trial_id="ssm-c1", strategy="control", integrity_ok_verified=1)
        self.assertNotIn("integrity_ok", rec)

    def test_diff_failure_flows_through_to_absent_key(self) -> None:
        post = dict(_PRE)
        post["README.md"] = "9" * 64
        verified = verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_CAPTURED)
        rec = self._build(
            trial_id="ssm-c1", strategy="control", integrity_ok_verified=verified
        )
        self.assertNotIn("integrity_ok", rec)

    def test_route_not_captured_flows_through_to_absent_key(self) -> None:
        post = dict(_PRE)
        verified = verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_NOT_CAPTURED)
        rec = self._build(
            trial_id="ssm-c1", strategy="control",
            integrity_ok_verified=verified, route_result=_ROUTE_NOT_CAPTURED,
        )
        self.assertNotIn("integrity_ok", rec)

    def test_forced_exception_flows_through_to_absent_key(self) -> None:
        verified = verify(_PRE, dict(_PRE), None, _ALLOWED, _ROUTE_CAPTURED)
        rec = self._build(
            trial_id="ssm-c1", strategy="control", integrity_ok_verified=verified
        )
        self.assertNotIn("integrity_ok", rec)

    def test_real_match_lane_keeps_observed_and_expected_strings(self) -> None:
        graded = RouteResult(
            captured=True, status="match", reason="ok",
            expected_model="high-tier-model", expected_effort="high",
            observed_model="high-tier-model", observed_effort="high", exit_code=0,
        )
        rec = self._build(
            trial_id="ssm-x1", strategy="sefi-chain-sequential",
            integrity_ok_verified=True, route_result=graded,
        )
        lane = rec["route_evidence"][0]
        self.assertEqual(lane["model"], "high-tier-model")
        self.assertEqual(lane["effort"], "high")
        self.assertEqual(lane["expected_model"], "high-tier-model")
        self.assertEqual(lane["expected_effort"], "high")

    def test_built_pair_loads_and_scores_through_scorecard(self) -> None:
        control = self._build(
            trial_id="ssm-c1", strategy="control", integrity_ok_verified=True
        )
        treatment = self._build(
            trial_id="ssm-x1", strategy="sefi-chain-sequential", integrity_ok_verified=True
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "trials.jsonl"
            with path.open("w", encoding="utf-8", newline="\n") as fh:
                for rec in (control, treatment):
                    fh.write(json.dumps(rec) + "\n")
            proc = subprocess.run(
                [sys.executable, str(SCORECARD), str(path)],
                capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scored trials (integrity_ok is true): 2", proc.stdout)
        self.assertIn("status=model=unchecked", proc.stdout)

    def test_excluded_pair_scores_zero_through_scorecard(self) -> None:
        # Records built from a failed verify() omit integrity_ok -> scorecard excludes them.
        post = dict(_PRE)
        post["README.md"] = "9" * 64
        bad = verify(_PRE, dict(_PRE), post, _ALLOWED, _ROUTE_CAPTURED)
        control = self._build(
            trial_id="ssm-c1", strategy="control", integrity_ok_verified=bad
        )
        treatment = self._build(
            trial_id="ssm-x1", strategy="sefi-chain-sequential", integrity_ok_verified=bad
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "trials.jsonl"
            with path.open("w", encoding="utf-8", newline="\n") as fh:
                for rec in (control, treatment):
                    fh.write(json.dumps(rec) + "\n")
            proc = subprocess.run(
                [sys.executable, str(SCORECARD), str(path)],
                capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scored trials (integrity_ok is true): 0", proc.stdout)
        self.assertIn("excluded (integrity_ok not true): 2", proc.stdout)


class AcceptanceEvalTests(unittest.TestCase):
    """Step 7: run.evaluate_acceptance -- pristine re-run + one chain rework pass."""

    def _make_check(self, tmp: Path) -> Path:
        # exit 0 iff <arg1>/marker exists -- a stand-in for a case acceptance check.
        chk = tmp / "check_marker.sh"
        chk.write_bytes(b'#!/usr/bin/env sh\ntest -f "${1:-.}/marker"\n')
        return chk

    def test_chain_reworks_once_then_accepts(self) -> None:
        from benchmarks.runner.run import evaluate_acceptance

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            chk = self._make_check(root)
            sb = root / "sb"
            sb.mkdir()
            calls: list[int] = []

            def rerun() -> None:
                calls.append(1)
                (sb / "marker").write_text("done", encoding="ascii")

            acc = evaluate_acceptance(
                strategy="sefi-chain", check_script=chk, sandbox_repo=sb, rerun_arm=rerun
            )
        self.assertEqual(calls, [1], "exactly one rework pass")
        self.assertEqual(
            acc,
            {"accepted": True, "first_pass_accepted": False, "rework_required": True},
        )

    def test_control_failure_is_just_not_accepted_no_rework(self) -> None:
        from benchmarks.runner.run import evaluate_acceptance

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            chk = self._make_check(root)
            sb = root / "sb"
            sb.mkdir()
            calls: list[int] = []

            acc = evaluate_acceptance(
                strategy="control",
                check_script=chk,
                sandbox_repo=sb,
                rerun_arm=lambda: calls.append(1),
            )
        self.assertEqual(calls, [], "control never reworks")
        self.assertEqual(
            acc,
            {"accepted": False, "first_pass_accepted": False, "rework_required": False},
        )

    def test_first_pass_accept_needs_no_rerun(self) -> None:
        from benchmarks.runner.run import evaluate_acceptance

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            chk = self._make_check(root)
            sb = root / "sb"
            sb.mkdir()
            (sb / "marker").write_text("done", encoding="ascii")
            calls: list[int] = []

            acc = evaluate_acceptance(
                strategy="sefi-chain-sequential",
                check_script=chk,
                sandbox_repo=sb,
                rerun_arm=lambda: calls.append(1),
            )
        self.assertEqual(calls, [])
        self.assertEqual(
            acc,
            {"accepted": True, "first_pass_accepted": True, "rework_required": False},
        )


class BudgetScanTests(unittest.TestCase):
    """Step 7: run.read_cap -- fail-closed budget line-scan (mirrors scorecard.py)."""

    def _cap(self, body: str):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "budget.yml"
            p.write_text(body, encoding="utf-8")
            from benchmarks.runner.run import read_cap

            return read_cap(p)

    def test_positive_value_is_returned(self) -> None:
        self.assertEqual(self._cap("benchmark_per_run_usd_cap: 15.00\n"), 15.0)

    def test_absent_key_is_none(self) -> None:
        self.assertIsNone(self._cap("other_key: 1\n"))

    def test_zero_and_negative_are_none(self) -> None:
        self.assertIsNone(self._cap("benchmark_per_run_usd_cap: 0\n"))
        self.assertIsNone(self._cap("benchmark_per_run_usd_cap: 0.0\n"))

    def test_live_budget_yml_has_a_usable_cap(self) -> None:
        from benchmarks.runner.run import read_cap

        self.assertIsInstance(read_cap(), float)


class EndToEndTests(_PinnedTempdirMixin, unittest.TestCase):
    """Step 8: run.py -> trials.jsonl -> scorecard.py, the first real end-to-end."""

    def _run(
        self,
        out: Path,
        *,
        mock_arm: Path,
        strategies: str = "control,sefi-chain-sequential",
        est: str = "0",
        check_route_cmd: str | None = None,
    ) -> int:
        from benchmarks.runner.run import main as run_main

        argv = [
            "--mock-arm", str(mock_arm),
            "--check-route-cmd", check_route_cmd or str(CHECK_ROUTE_STUB),
            "--cases", "sh-strict-mode",
            "--strategies", strategies,
            "--harness", "claude-code",
            "--tier", "mid",
            "--est-cost-per-trial", est,
            "--out", str(out),
        ]
        return run_main(argv)

    def _records(self, out: Path) -> list[dict]:
        lines = (out / "trials.jsonl").read_text(encoding="utf-8").splitlines()
        return [json.loads(ln) for ln in lines if ln.strip()]

    def _score(self, out: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCORECARD), str(out / "trials.jsonl")],
            capture_output=True,
            text=True,
        )

    def _no_leftover_scratch(self) -> None:
        # FIX F: assert against this test's PRIVATE pinned tempdir, not a global
        # %TEMP% glob a concurrent runner / qa process could pollute.
        self._assert_no_scratch_leak()

    def test_green_run_scores_two_trials(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run1"
            rc = self._run(out, mock_arm=MOCK_ARM)
            self.assertEqual(rc, 0)
            self.assertTrue((out / "trials.jsonl").is_file())
            recs = self._records(out)
            self.assertEqual(len(recs), 2)
            for rec in recs:
                self.assertIs(rec.get("integrity_ok"), True)
            self._no_leftover_scratch()

            proc = self._score(out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("scored trials (integrity_ok is true): 2", proc.stdout)
            self.assertIn("route-correctness", proc.stdout)
            self.assertIn("== aggregate deltas", proc.stdout)

    def test_tamper_run_is_excluded_by_scorecard(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run3"
            rc = self._run(out, mock_arm=MOCK_ARM_TAMPER)
            self.assertEqual(rc, 0)
            recs = self._records(out)
            self.assertEqual(len(recs), 2)
            for rec in recs:
                self.assertNotIn("integrity_ok", rec)
            self._no_leftover_scratch()

            proc = self._score(out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("scored trials (integrity_ok is true): 0", proc.stdout)
            self.assertIn("excluded (integrity_ok not true): 2", proc.stdout)

    def test_budget_abort_produces_no_trials_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run4"
            rc = self._run(out, mock_arm=MOCK_ARM, est="999")
            self.assertEqual(rc, 0)
            self.assertTrue((out / "ABORTED.md").is_file())
            self.assertFalse((out / "trials.jsonl").exists())
            self._no_leftover_scratch()

    def test_route_not_captured_run_is_excluded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run5"
            rc = self._run(out, mock_arm=MOCK_ARM, check_route_cmd="/nonexistent")
            self.assertEqual(rc, 0)
            recs = self._records(out)
            self.assertEqual(len(recs), 2)
            for rec in recs:
                self.assertNotIn("integrity_ok", rec)
            self._no_leftover_scratch()

            proc = self._score(out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("scored trials (integrity_ok is true): 0", proc.stdout)


def _load_case(case_id: str) -> dict:
    data = json.loads(
        (REPO_ROOT / "benchmarks" / "cases.json").read_text(encoding="utf-8")
    )
    return next(c for c in data["cases"] if c["case_id"] == case_id)


class RefManifestTests(unittest.TestCase):
    """FIX 7: integrity check 1 (`pre == ref`) is a real check against a DEDICATED
    once-per-run baseline clone, not a per-trial `dict(pre)` tautology."""

    def _run_trial(self, ref_manifest: dict, out: Path) -> dict:
        from benchmarks.runner.run import resolve_check_script, run_trial

        case = _load_case("sh-strict-mode")
        return run_trial(
            case=case,
            strategy="control",
            harness="claude-code",
            trial_index=1,
            out_dir=out,
            timeout_s=30,
            mock_arm=MOCK_ARM,
            check_route_cmd=str(CHECK_ROUTE_STUB),
            tier="mid",
            pinned_ref="HEAD",
            check_script=resolve_check_script(case),
            ref_manifest=ref_manifest,
        )

    def test_matching_baseline_passes_check_one(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as sb:
            baseline = snapshot(sb)
        with tempfile.TemporaryDirectory() as tmp:
            rec = self._run_trial(baseline, Path(tmp))
        self.assertIs(rec.get("integrity_ok"), True)

    def test_perturbed_pre_vs_baseline_fails_check_one(self) -> None:
        with sandbox(REPO_ROOT, "HEAD") as sb:
            baseline = snapshot(sb)
        perturbed = dict(baseline)
        perturbed["zzz/not-a-real-file"] = "0" * 64  # pre (real clone) != this ref
        with tempfile.TemporaryDirectory() as tmp:
            rec = self._run_trial(perturbed, Path(tmp))
        self.assertNotIn("integrity_ok", rec)

    def test_dedicated_ref_clone_built_once_per_run(self) -> None:
        import benchmarks.runner.run as runmod

        real_sandbox = runmod.sandbox
        calls = {"n": 0}

        def counting(*a, **kw):
            calls["n"] += 1
            return real_sandbox(*a, **kw)

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            with mock.patch.object(runmod, "sandbox", counting):
                rc = runmod.main([
                    "--mock-arm", str(MOCK_ARM),
                    "--check-route-cmd", str(CHECK_ROUTE_STUB),
                    "--cases", "sh-strict-mode",
                    "--strategies", "control,sefi-chain-sequential",
                    "--harness", "claude-code", "--tier", "mid",
                    "--est-cost-per-trial", "0", "--out", str(out),
                ])
        self.assertEqual(rc, 0)
        # 1 dedicated baseline clone + 1 clone per trial (2 trials) == 3.
        self.assertEqual(calls["n"], 3)


class FatalAndPreflightTests(unittest.TestCase):
    """FIX 4 + FIX 6: a bad --harness is a usage error (exit 2, no out dir); a fatal
    mid-run error writes ABORTED.md and exits 0; a real run needs a positive est cost."""

    def _argv(self, out: Path, **over) -> list[str]:
        base = {
            "--mock-arm": str(MOCK_ARM),
            "--check-route-cmd": str(CHECK_ROUTE_STUB),
            "--cases": "sh-strict-mode",
            "--strategies": "control,sefi-chain-sequential",
            "--harness": "claude-code",
            "--tier": "mid",
            "--est-cost-per-trial": "0",
            "--out": str(out),
        }
        base.update(over)
        argv: list[str] = []
        for k, v in base.items():
            if v is None:
                continue
            argv += [k, v]
        return argv

    def _expect_usage_error(self, argv: list[str]) -> int:
        import contextlib
        import io

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as ctx:
                from benchmarks.runner.run import main as run_main

                run_main(argv)
        return ctx.exception.code

    def test_bad_harness_is_exit_2_and_creates_no_out_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            code = self._expect_usage_error(self._argv(out, **{"--harness": "bogus"}))
            self.assertEqual(code, 2)
            self.assertFalse(out.exists(), "no output dir on a usage error")

    def test_bad_strategy_is_exit_2_and_creates_no_out_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            code = self._expect_usage_error(self._argv(out, **{"--strategies": "xyz"}))
            self.assertEqual(code, 2)
            self.assertFalse(out.exists())

    def test_fatal_midloop_error_writes_aborted_md_and_exits_0(self) -> None:
        import benchmarks.runner.run as runmod

        def boom(**kw):
            raise RuntimeError("injected mid-loop failure")

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            with mock.patch.object(runmod, "run_trial", boom):
                rc = runmod.main(self._argv(out))
            self.assertEqual(rc, 0)
            self.assertTrue((out / "ABORTED.md").is_file())
            self.assertIn("fatal:", (out / "ABORTED.md").read_text(encoding="utf-8"))
            self.assertFalse((out / "trials.jsonl").exists())

    def test_real_run_without_est_cost_preflight_aborts(self) -> None:
        from benchmarks.runner.run import main as run_main

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            # No --mock-arm: a REAL run. est cost 0 -> the $cap can never bind -> abort.
            rc = run_main(self._argv(out, **{"--mock-arm": None}))
            self.assertEqual(rc, 0)
            self.assertTrue((out / "ABORTED.md").is_file())
            self.assertIn(
                "positive --est-cost-per-trial",
                (out / "ABORTED.md").read_text(encoding="utf-8"),
            )
            self.assertFalse((out / "trials.jsonl").exists())
            # FIX G: the dedicated baseline ref clone is built AFTER the pre-flight
            # aborts, so an immediate pre-flight abort writes no ref.manifest.
            self.assertFalse((out / "ref.manifest").exists())

    def test_nonempty_out_dir_is_refused_and_contents_untouched(self) -> None:
        # FIX B: a pre-populated --out -> SystemExit 2 BEFORE any mkdir/abort, with the
        # existing bytes untouched and no ABORTED.md written.
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            out.mkdir()
            sentinel = out / "trials.jsonl"
            sentinel.write_text('{"prior": "run"}\n', encoding="utf-8")
            before = sentinel.read_bytes()
            code = self._expect_usage_error(self._argv(out))
            self.assertEqual(code, 2)
            self.assertEqual(sentinel.read_bytes(), before, "prior artifacts must be untouched")
            self.assertFalse((out / "ABORTED.md").exists(), "no ABORTED.md on a usage error")

    def test_mock_run_with_zero_est_cost_still_runs(self) -> None:
        from benchmarks.runner.run import main as run_main

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            rc = run_main(self._argv(out))
            self.assertEqual(rc, 0)
            self.assertTrue((out / "trials.jsonl").is_file())


class ForgeryTests(unittest.TestCase):
    """FIX 1: an arm cannot forge a scoreable <out>/trials.jsonl.

    The arm scratch is isolated from the results dir and the results-dir path is never
    disclosed to the arm; the runner removes a stale trials.jsonl at startup, refuses to
    finalize over a pre-existing one, and unlinks any raced-in one on an abort.
    """

    def _argv(self, out: Path, mock_arm: Path, est: str) -> list[str]:
        return [
            "--mock-arm", str(mock_arm),
            "--check-route-cmd", str(CHECK_ROUTE_STUB),
            "--cases", "sh-strict-mode",
            "--strategies", "control,sefi-chain-sequential",
            "--harness", "claude-code", "--tier", "mid",
            "--est-cost-per-trial", est, "--out", str(out),
        ]

    def test_forge_on_clean_run_keeps_only_the_real_records(self) -> None:
        from benchmarks.runner.run import main as run_main

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            rc = run_main(self._argv(out, MOCK_ARM_FORGE, "0"))
            self.assertEqual(rc, 0)
            recs = [
                json.loads(ln)
                for ln in (out / "trials.jsonl").read_text(encoding="utf-8").splitlines()
                if ln.strip()
            ]
        self.assertEqual(len(recs), 2)
        for rec in recs:
            self.assertTrue(rec["trial_id"].startswith("sh-strict-mode-"))
            self.assertNotIn("forged", rec["trial_id"])
            # the arm's forgery landed nowhere the runner reads -> real trial still clean.
            self.assertIs(rec.get("integrity_ok"), True)

    def test_forge_on_budget_abort_leaves_no_trials_jsonl(self) -> None:
        import benchmarks.runner.run as runmod

        real_run_trial = runmod.run_trial

        def racing(**kw):
            # Simulate an arm that raced a trials.jsonl into --out mid-run (something the
            # isolation in arms.py now prevents, but the abort path must still be robust).
            rec = real_run_trial(**kw)
            (kw["out_dir"] / "trials.jsonl").write_text('{"raced": true}\n', encoding="ascii")
            return rec

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "run"
            with mock.patch.object(runmod, "run_trial", racing):
                # est 8 vs the $15 cap: trial 1 runs (and races a file in), trial 2 aborts.
                rc = runmod.main(self._argv(out, MOCK_ARM_FORGE, "8"))
            self.assertEqual(rc, 0)
            self.assertTrue((out / "ABORTED.md").is_file())
            self.assertFalse(
                (out / "trials.jsonl").exists(),
                "the abort path must unlink a raced-in trials.jsonl (FIX 1b)",
            )


if __name__ == "__main__":
    unittest.main()
