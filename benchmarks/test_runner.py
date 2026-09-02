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

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    # Under pytest's default import mode only benchmarks/ lands on sys.path, so the
    # ``benchmarks.runner`` package would not import. Mirrors nothing in test_scorecard.py
    # (which shells out instead); this suite imports the runner modules under test.
    sys.path.insert(0, str(REPO_ROOT))

from benchmarks.runner.arms import ArmResult, run_arm  # noqa: E402
from benchmarks.runner.route import capture_route  # noqa: E402
from benchmarks.runner.sandbox import resolve_git, resolve_python, sandbox  # noqa: E402
from benchmarks.runner.snapshot import diff, snapshot  # noqa: E402

# A tracked file under benchmarks/ used for the check-attr assertion. check_sh-strict-mode.sh
# exists on this branch (benchmarks/cases/), so no substitution was needed.
CHECK_ATTR_TARGET = "benchmarks/cases/check_sh-strict-mode.sh"

FIXTURES = REPO_ROOT / "benchmarks" / "runner" / "fixtures"
MOCK_ARM = FIXTURES / "mock_arm.py"
MOCK_ARM_SLOW = FIXTURES / "mock_arm_slow.py"
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


class ArmsTests(unittest.TestCase):
    """Step 4: benchmarks/runner/arms.run_arm -- all via the --mock-arm seam."""

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


if __name__ == "__main__":
    unittest.main()
