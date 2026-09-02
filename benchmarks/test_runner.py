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

from benchmarks.runner.sandbox import resolve_git, resolve_python, sandbox  # noqa: E402
from benchmarks.runner.snapshot import diff, snapshot  # noqa: E402

# A tracked file under benchmarks/ used for the check-attr assertion. check_sh-strict-mode.sh
# exists on this branch (benchmarks/cases/), so no substitution was needed.
CHECK_ATTR_TARGET = "benchmarks/cases/check_sh-strict-mode.sh"


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


if __name__ == "__main__":
    unittest.main()
