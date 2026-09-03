#!/usr/bin/env python3
"""Runner entrypoint for the out-of-process blinded paired A/B benchmark.

This is the FIRST real end-to-end wiring: for each ``case x strategy x trial`` it builds
a real ``git clone`` sandbox (``sandbox.py``), pre-snapshots it (``snapshot.py``), runs
one arm inside it (``arms.py``), re-runs the case acceptance check from a PRISTINE
out-of-sandbox copy, post-snapshots, captures route evidence out-of-process
(``route.py``), runs the fail-closed integrity gate (``integrity.py``), and stages one
runner-written record (``record.py``) to ``<out>/trials.partial.jsonl``.

Budget is fail-closed: an absent / non-finite / non-positive ``benchmark_per_run_usd_cap``
in ``config/budget.yml`` ABORTS before any arm runs (no run beats an unbounded run); a
running cost ceiling stops the matrix before a trial that would cross the cap. On ANY
abort the runner writes ``<out>/ABORTED.md``, leaves ``trials.partial.jsonl`` in place,
and NEVER creates ``<out>/trials.jsonl`` -- so an aborted run has nothing to score. Only
a clean, within-budget completion of the full matrix copies
``trials.partial.jsonl -> trials.jsonl`` (write-temp-then-rename).

``run.py`` exits 0 on a completed OR a cleanly aborted run (budget, cost-ceiling, or a
fatal mid-run error -- all write ``ABORTED.md``); non-zero ONLY on a usage / argument
error (a bad ``--strategies`` / ``--harness``, an unknown case, etc. -- exit 2, no output
dir created).

Trust boundary, stated honestly: no arm-written VALUE is a scoring input, and the arm is
never told the results-dir path (``arms.py`` isolates all arm scratch). Wholesale
artifact forgery -- an arm dropping its own ``trials.jsonl`` somewhere -- is NOT prevented
without OS-level isolation (a container), which this version does not use. Mitigations:
arm scratch is isolated from the results dir; the results-dir path is never disclosed to
the arm; ``--out`` must be a new / empty directory (a non-empty one is refused with
SystemExit 2, never cleaned); the runner refuses to finalize over a pre-existing
``trials.jsonl`` and unlinks any raced-in one on an abort.

Standard library only: argparse, json, math, os, re, shutil, subprocess, sys, tempfile,
pathlib.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    # Run as ``python benchmarks/runner/run.py`` Python puts THIS file's dir on sys.path,
    # not the repo root, so ``benchmarks.runner`` would not import. Mirrors
    # benchmarks/test_runner.py's sys.path guard.
    sys.path.insert(0, str(_REPO_ROOT))

from benchmarks.runner import integrity  # noqa: E402
from benchmarks.runner.arms import _HARNESSES, _redact_text, run_arm  # noqa: E402
from benchmarks.runner.record import build_record  # noqa: E402
from benchmarks.runner.route import capture_route  # noqa: E402
from benchmarks.runner.sandbox import resolve_git, sandbox  # noqa: E402
from benchmarks.runner.snapshot import snapshot  # noqa: E402

CASES_JSON = _REPO_ROOT / "benchmarks" / "cases.json"
BUDGET_YML = _REPO_ROOT / "config" / "budget.yml"
BUDGET_KEY = "benchmark_per_run_usd_cap"

_STRATEGIES = ("control", "sefi-chain", "sefi-chain-sequential")
_CHAIN_STRATEGIES = ("sefi-chain", "sefi-chain-sequential")

# record.py emits exactly one route lane per trial; scorecard.py requires
# ``model_calls >= len(route_evidence)`` (scorecard.py:230).
_ROUTE_LANES_PER_TRIAL = 1

# No harness exposes a per-call model-call count in this version. This is a PLACEHOLDER,
# not an observation: ``model_calls`` is emitted only as a floor (see below) so the record
# satisfies the scorer's route-lane invariant. ``model_calls_delta`` in the scorecard is
# therefore a difference of two constants, not a measured quantity.
_MODEL_CALLS_UNKNOWN = 0

_CHECK_SCRIPT_RE = re.compile(r"(\S+\.sh)")

# ---------------------------------------------------------------------------
# budget line-scan -- mirrors scorecard.py:265-306 (_parse_ceiling), no YAML dep
# ---------------------------------------------------------------------------

_CAP_KEY_ABSENT = object()


def _parse_cap(text: str):
    """Positive finite USD cap parsed from budget.yml ``text``.

    ``_CAP_KEY_ABSENT`` when the key does not appear; ``None`` when it appears but is
    non-numeric / non-finite / not strictly positive. Only a strictly-positive finite
    float is returned as a number. Same shape as ``scorecard._parse_ceiling``.
    """
    for line in text.splitlines():
        m = re.match(
            r"\s*" + re.escape(BUDGET_KEY) + r"\s*:\s*([0-9]+(?:\.[0-9]+)?)",
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
    return _CAP_KEY_ABSENT


def read_cap(path: Path = BUDGET_YML) -> float | None:
    """The per-run USD cap, or ``None`` if it is absent / unreadable / non-positive.

    ``None`` is the fail-closed signal: the caller ABORTS before any arm runs.
    """
    try:
        parsed = _parse_cap(path.read_text(encoding="utf-8"))
    except OSError:
        return None
    if parsed is _CAP_KEY_ABSENT or parsed is None:
        return None
    return parsed


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _resolve_sh() -> str:
    """Absolute path to a POSIX shell by a validated PATH walk (isfile + X_OK).

    A bare ``sh`` / ``bash`` on Windows is resolved by CreateProcess (System32 first ->
    WSL relay stub). Mirrors ``route._resolve_bash``. Tries ``sh`` then ``bash`` -- the
    case ``acceptance_check`` strings are ``sh <script> .``.
    """
    names = (
        ("sh.exe", "sh", "bash.exe", "bash")
        if os.name == "nt"
        else ("sh", "bash")
    )
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    raise RuntimeError("no sh/bash found on PATH (validated isfile + X_OK walk)")


def _git_head() -> str:
    git = resolve_git()
    proc = subprocess.run(
        [git, "-C", str(_REPO_ROOT), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


def resolve_check_script(case: dict) -> Path:
    """Absolute path to the case's acceptance-check script from the PRISTINE base
    checkout -- ``<repo-root>/<relpath>`` -- NEVER the sandbox copy.

    The check script is resolved from the base checkout by absolute path, with a
    ``relative_to`` escape guard, and run as an argv list (never a shell string, never the
    sandbox copy). The relpath is taken from the case ``acceptance_check`` string (e.g.
    ``sh benchmarks/cases/check_sh-strict-mode.sh .``); the arm-authored check string in
    the trial worktree is NEVER executed. Base-checkout integrity itself is not enforced
    without OS-level isolation.
    """
    ac = str(case.get("acceptance_check", ""))
    m = _CHECK_SCRIPT_RE.search(ac)
    if not m:
        raise ValueError(f"case {case.get('case_id')!r}: no *.sh script in acceptance_check {ac!r}")
    rel = m.group(1)
    script = (_REPO_ROOT / rel).resolve()
    try:
        script.relative_to(_REPO_ROOT)
    except ValueError as exc:
        raise ValueError(f"case {case.get('case_id')!r}: check script escapes repo root: {rel!r}") from exc
    if not script.is_file():
        raise ValueError(f"case {case.get('case_id')!r}: pristine check script missing: {script}")
    return script


def _run_check(check_script: Path, sandbox_repo) -> bool:
    """Run the pristine check against the sandbox post-state. Exit 0 -> accepted."""
    sh = _resolve_sh()
    proc = subprocess.run(
        [sh, str(check_script), Path(sandbox_repo).as_posix()],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0


def evaluate_acceptance(*, strategy: str, check_script: Path, sandbox_repo, rerun_arm) -> dict:
    """Grade a trial by re-running the PRISTINE check against the sandbox post-state.

    ``first_pass_accepted`` is the first run's verdict. If it fails AND ``strategy`` is a
    chain (whose own review can call for rework), ONE rework pass is allowed:
    ``rerun_arm()`` re-invokes the arm in the SAME sandbox, then the pristine check is
    re-run and its verdict becomes ``accepted`` with ``rework_required=True``. A control
    failure is simply ``accepted=False`` (no rework). Independently unit-testable with a
    fail-then-pass mock.
    """
    first_pass_accepted = _run_check(check_script, sandbox_repo)
    accepted = first_pass_accepted
    rework_required = False
    if not first_pass_accepted and strategy in _CHAIN_STRATEGIES:
        rework_required = True
        rerun_arm()
        accepted = _run_check(check_script, sandbox_repo)
    return {
        "accepted": bool(accepted),
        "first_pass_accepted": bool(first_pass_accepted),
        "rework_required": bool(rework_required),
    }


def _write_manifest(path: Path, manifest: dict) -> None:
    path.write_text(
        json.dumps(manifest, sort_keys=True, indent=0) + "\n", encoding="utf-8"
    )


def _abort(out_dir: Path, reason: str, *, final: Path | None = None) -> None:
    """Write ``<out>/ABORTED.md`` and guarantee no scoreable ``trials.jsonl`` survives.

    If ``final`` exists (a stale artifact, or an arm raced a write into the results dir),
    it is unlinked here and the removal is noted in ``ABORTED.md``. The caller must NOT
    create ``trials.jsonl`` after an abort.
    """
    removed_note = ""
    if final is not None and final.exists():
        final.unlink()
        removed_note = (
            f"\nA pre-existing `{final.name}` was found and REMOVED -- an aborted run is\n"
            "never scoreable, and the runner never finalizes over a file it did not write.\n"
        )
    (out_dir / "ABORTED.md").write_text(
        "# benchmark run aborted\n\n"
        f"reason: {reason}\n"
        f"{removed_note}\n"
        "No `trials.jsonl` was produced. `trials.partial.jsonl` (if present) holds only\n"
        "the trials that completed before the abort and is NOT scoreable.\n",
        encoding="utf-8",
    )


# ---------------------------------------------------------------------------
# one trial
# ---------------------------------------------------------------------------


def run_trial(
    *,
    case: dict,
    strategy: str,
    harness: str,
    trial_index: int,
    out_dir: Path,
    timeout_s: float,
    mock_arm: Path | None,
    check_route_cmd: str | os.PathLike[str] | None,
    tier: str,
    pinned_ref: str,
    check_script: Path,
    ref_manifest: dict,
) -> dict:
    """Execute one ``case x strategy x trial`` and return its runner-written record.

    ``ref_manifest`` is the cached known-good baseline: ``snapshot()`` of a DEDICATED
    clean ``sandbox()`` clone at ``pinned_ref``, computed ONCE per run by ``main()`` and
    reused for every trial. Integrity check 1 (``pre == ref``) then genuinely catches a
    per-trial clone that came out different from that baseline (a corrupted clone, an
    autocrlf leak, a disk fault) -- it is no longer a by-construction tautology.
    """
    case_id = case["case_id"]
    trial_id = f"{case_id}-{strategy}-t{trial_index}"
    allowed_paths = list(case.get("allowed_paths", []))
    prompt_text = (_REPO_ROOT / case["prompt_file"]).read_text(encoding="utf-8")

    with sandbox(_REPO_ROOT, pinned_ref) as sb:
        pre = snapshot(sb)
        _write_manifest(out_dir / f"pre-{trial_id}.manifest", pre)
        _write_manifest(out_dir / f"ref-{trial_id}.manifest", ref_manifest)

        arm_result = run_arm(
            strategy,
            harness,
            prompt_text,
            sb,
            timeout_s,
            mock_arm=str(mock_arm) if mock_arm is not None else None,
            results_dir=out_dir,
        )

        def _rerun_arm() -> None:
            run_arm(
                strategy,
                harness,
                prompt_text,
                sb,
                timeout_s,
                mock_arm=str(mock_arm) if mock_arm is not None else None,
                results_dir=out_dir,
            )

        acceptance = evaluate_acceptance(
            strategy=strategy,
            check_script=check_script,
            sandbox_repo=sb,
            rerun_arm=_rerun_arm,
        )

        post = snapshot(sb)
        _write_manifest(out_dir / f"post-{trial_id}.manifest", post)

        route_result = capture_route(
            harness, tier, arm_result.session_record_ref, check_route_cmd=check_route_cmd
        )
        integrity_ok = integrity.verify(
            pre, ref_manifest, post, allowed_paths, route_result
        )

    # SYNTHETIC FLOOR, not a measurement: no harness reports a per-call count in this
    # version, so model_calls is emitted only as a floor of 1 (one arm invocation) to
    # satisfy the scorer's route-lane invariant (scorecard.py:230,
    # model_calls >= len(route_evidence)). See _MODEL_CALLS_UNKNOWN.
    model_calls = max(_MODEL_CALLS_UNKNOWN, _ROUTE_LANES_PER_TRIAL)

    return build_record(
        trial_id=trial_id,
        case_id=case_id,
        trial=trial_index,
        strategy=strategy,
        harness=harness,
        acceptance_checks=[check_script.stem],
        acceptance=acceptance,
        wall_time_seconds=arm_result.wall_time_s,
        model_calls=model_calls,
        case_fingerprint=case["case_fingerprint"],
        route_result=route_result,
        integrity_ok_verified=integrity_ok,
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="run.py",
        description=(
            "Out-of-process blinded paired A/B benchmark runner. Builds a real git-clone "
            "sandbox per trial, runs one arm inside it, verifies integrity out-of-process, "
            "and stages runner-written trial records. Standard library only."
        ),
    )
    p.add_argument("--cases", required=True, help="comma-separated case ids from benchmarks/cases.json")
    p.add_argument("--strategies", required=True, help="comma list from control,sefi-chain,sefi-chain-sequential")
    p.add_argument("--harness", required=True, help="harness name (claude-code, codex, opencode)")
    p.add_argument("--out", required=True, help="output dir for manifests / records / ABORTED.md")
    p.add_argument("--trials", type=int, default=1, help="trials per case x strategy (default 1)")
    p.add_argument("--timeout-s", type=float, default=900.0, help="per-arm subprocess timeout (default 900)")
    p.add_argument("--est-cost-per-trial", type=float, default=0.0, help="USD estimate per trial for the running ceiling (default 0)")
    p.add_argument("--mock-arm", default=None, help="test-only: path to a local Python mock arm")
    p.add_argument("--check-route-cmd", default=None, help="test-only: path to a check-route.sh stub")
    p.add_argument("--tier", default="flexible", help="routing tier passed to capture_route (default flexible)")
    p.add_argument("--ref", default=None, help="pinned git ref (default: current HEAD of the repo)")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    strategies = [s.strip() for s in args.strategies.split(",") if s.strip()]
    bad = [s for s in strategies if s not in _STRATEGIES]
    if not strategies or bad:
        parser.error(f"--strategies must be a comma list from {','.join(_STRATEGIES)}; bad: {bad}")

    # Validate --harness HERE (usage error: exit 2, no output dir created), alongside
    # --strategies -- not deep inside run_arm after the out dir and manifests exist.
    if args.harness not in _HARNESSES:
        parser.error(f"--harness must be one of {','.join(_HARNESSES)}; got {args.harness!r}")

    case_ids = [c.strip() for c in args.cases.split(",") if c.strip()]
    if not case_ids:
        parser.error("--cases must be a non-empty comma list of case ids")

    if args.trials < 1:
        parser.error("--trials must be >= 1")
    if not math.isfinite(args.est_cost_per_trial) or args.est_cost_per_trial < 0:
        parser.error("--est-cost-per-trial must be a finite value >= 0")
    if not math.isfinite(args.timeout_s) or args.timeout_s <= 0:
        parser.error("--timeout-s must be a finite value > 0")

    try:
        cases_data = json.loads(CASES_JSON.read_text(encoding="utf-8"))
    except OSError as exc:
        parser.error(f"cannot read {CASES_JSON}: {exc}")
    by_id = {c["case_id"]: c for c in cases_data.get("cases", [])}
    missing = [c for c in case_ids if c not in by_id]
    if missing:
        parser.error(f"unknown case id(s): {missing}")
    cases = [by_id[c] for c in case_ids]

    mock_arm: Path | None = None
    if args.mock_arm:
        try:
            mock_arm = Path(args.mock_arm).resolve(strict=True)
        except OSError as exc:
            parser.error(f"--mock-arm not found: {exc}")

    # --check-route-cmd may deliberately be a non-existent path (route.py fails closed).
    check_route_cmd = args.check_route_cmd

    try:
        check_scripts = {c["case_id"]: resolve_check_script(c) for c in cases}
    except ValueError as exc:
        parser.error(str(exc))

    out_dir = Path(args.out)
    # Refuse a non-empty output dir (SystemExit 2) BEFORE mkdir -- the runner never
    # deletes a prior run's artifacts (run-sefi-benchmark/SKILL.md:130-134,145). A
    # nonexistent or empty --out proceeds.
    # F-E: --out at an existing NON-directory (a regular file) would make ``iterdir()``
    # raise an uncaught NotADirectoryError; turn it -- and any other OSError from the
    # emptiness probe -- into the intended SystemExit 2.
    if out_dir.exists() and not out_dir.is_dir():
        parser.error(f"--out path {out_dir} exists and is not a directory")
    try:
        out_dir_nonempty = out_dir.exists() and any(out_dir.iterdir())
    except OSError as exc:
        parser.error(f"cannot inspect output directory {out_dir}: {exc}")
    if out_dir_nonempty:
        parser.error(
            f"output directory {out_dir} is not empty; choose a new empty directory"
        )
    out_dir.mkdir(parents=True, exist_ok=True)
    partial = out_dir / "trials.partial.jsonl"
    final = out_dir / "trials.jsonl"

    try:
        pinned_ref = args.ref if args.ref else _git_head()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        parser.error(f"cannot resolve pinned ref: {exc}")

    # BUDGET pre-flight (fail-closed): no usable cap -> abort before any arm runs.
    cap = read_cap()
    if cap is None:
        _abort(
            out_dir,
            f"budget pre-flight: {BUDGET_KEY} in config/budget.yml is absent, "
            "non-finite, or <= 0 -- no run beats an unbounded run",
            final=final,
        )
        return 0

    est = float(args.est_cost_per_trial)

    # COST-CEILING pre-flight (fail-closed): a REAL run (no --mock-arm) with a
    # non-positive --est-cost-per-trial has NOTHING to accumulate, so the running ceiling
    # below is inert -- the $cap would never bind. Refuse it. A --mock-arm run (zero
    # spend by construction) may keep 0.
    if mock_arm is None and est <= 0:
        _abort(
            out_dir,
            f"a real run requires a positive --est-cost-per-trial so the ${cap:.2f} "
            "ceiling can bind (a --mock-arm run may pass 0)",
            final=final,
        )
        return 0

    _write_manifest(
        out_dir / "run.json",
        {
            "pinned_ref": pinned_ref,
            "harness": args.harness,
            "tier": args.tier,
            "cases": case_ids,
            "strategies": strategies,
            "trials": args.trials,
            "budget_cap_usd": cap,
            "est_cost_per_trial_usd": args.est_cost_per_trial,
        },
    )

    running_total = 0.0
    aborted = False
    try:
        # FIX 7a: one DEDICATED clean clone at pinned_ref, snapshotted ONCE per run, is
        # the known-good baseline reused for every trial's integrity check 1. Not a
        # per-trial tautology -- it catches a per-trial clone that came out different.
        with sandbox(_REPO_ROOT, pinned_ref) as ref_sb:
            ref_manifest = snapshot(ref_sb)
        _write_manifest(out_dir / "ref.manifest", ref_manifest)

        with partial.open("w", encoding="utf-8", newline="\n") as fh:
            for case in cases:
                if aborted:
                    break
                for strategy in strategies:
                    if aborted:
                        break
                    for trial_index in range(1, args.trials + 1):
                        # BUDGET running ceiling: stop BEFORE a trial that would push the
                        # running total past the cap.
                        if est > 0 and running_total + est > cap:
                            _abort(
                                out_dir,
                                f"running cost ceiling ${cap:.2f} would be exceeded: "
                                f"${running_total:.2f} spent + ${est:.2f} est for the next trial",
                                final=final,
                            )
                            aborted = True
                            break
                        record = run_trial(
                            case=case,
                            strategy=strategy,
                            harness=args.harness,
                            trial_index=trial_index,
                            out_dir=out_dir,
                            timeout_s=args.timeout_s,
                            mock_arm=mock_arm,
                            check_route_cmd=check_route_cmd,
                            tier=args.tier,
                            pinned_ref=pinned_ref,
                            check_script=check_scripts[case["case_id"]],
                            ref_manifest=ref_manifest,
                        )
                        fh.write(json.dumps(record) + "\n")
                        fh.flush()
                        running_total += est
    except Exception as exc:  # noqa: BLE001 -- any fatal mid-run error is a clean abort
        # FIX 4b: a fatal error mid-run writes ABORTED.md (not a bare non-zero exit),
        # removes any raced trials.jsonl, leaves trials.partial.jsonl, and returns 0.
        # "non-zero ONLY on a usage/arg error" now holds.
        # qa-Minor-3: an OSError message can carry an absolute home path -- redact it to
        # ``~`` before it lands in ABORTED.md, same rule as the arm raw log.
        _abort(out_dir, _redact_text(f"fatal: {exc}"), final=final)
        return 0

    if aborted:
        # trials.partial.jsonl is left in place; trials.jsonl is NEVER created.
        return 0

    # CLEAN completion: stage trials.partial.jsonl -> trials.jsonl (temp then rename).
    # FIX 1b: if trials.jsonl already exists here, an arm raced a write into the results
    # dir -- treat it as an abort, do NOT create the real file.
    if final.exists():
        _abort(
            out_dir,
            "a trials.jsonl already existed at finalize time -- the runner never writes "
            "over a file it did not create; treating as an aborted run",
            final=final,
        )
        return 0
    tmp = out_dir / "trials.jsonl.tmp"
    shutil.copyfile(partial, tmp)
    os.replace(tmp, final)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
