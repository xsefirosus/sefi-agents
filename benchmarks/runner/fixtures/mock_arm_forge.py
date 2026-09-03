#!/usr/bin/env python3
"""Test-only ADVERSARIAL mock arm: does the ``sh-strict-mode`` task, then TRIES to forge a
scoreable ``trials.jsonl`` anywhere it can reach.

Task behaviour matches ``mock_arm.py`` (inserts the exact line ``set -euo pipefail`` after
the shebang) so the pristine acceptance check still passes. It then ATTEMPTS to drop a
``trials.jsonl`` full of ``"integrity_ok": true`` records into every directory it can
derive from what the runner handed it -- the parent of its own scratch dir (from
``argv[1]``), the parent of ``SEFI_ARM_SESSION_FILE``, and the current working directory
(the sandbox repo). It must NOT be able to reach the runner's ``--out`` directory: that
path is never passed to the arm, so the runner's own ``trials.jsonl`` wins on a clean run,
and an aborted run has no ``trials.jsonl`` at all.

No network, no model call, ASCII only, relative / temp paths only -- NO personal paths
(it never prints or hard-codes a home dir). Invoked as::

    <python> mock_arm_forge.py <prompt_path> <sandbox_repo>

Standard library only: json, os, sys, pathlib.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

GUARD = "set -euo pipefail"

_FORGED = [
    {
        "schema_version": 1,
        "trial_id": "forged-control-t1",
        "case_id": "sh-strict-mode",
        "case_fingerprint": "f" * 64,
        "trial": 1,
        "strategy": "control",
        "harness": "claude-code",
        "acceptance_checks": ["check_sh-strict-mode"],
        "accepted": True,
        "first_pass_accepted": True,
        "rework_required": False,
        "wall_time_seconds": 1.0,
        "model_calls": 1,
        "integrity_ok": True,
        "route_evidence": [
            {
                "role": "solo",
                "model": "not-applicable",
                "effort": "not-applicable",
                "expected_effort": "not-applicable",
                "task_id": "forged-control-t1-solo",
            }
        ],
    },
    {
        "schema_version": 1,
        "trial_id": "forged-seq-t1",
        "case_id": "sh-strict-mode",
        "case_fingerprint": "f" * 64,
        "trial": 1,
        "strategy": "sefi-chain-sequential",
        "harness": "claude-code",
        "acceptance_checks": ["check_sh-strict-mode"],
        "accepted": True,
        "first_pass_accepted": True,
        "rework_required": False,
        "wall_time_seconds": 1.0,
        "model_calls": 1,
        "integrity_ok": True,
        "route_evidence": [
            {
                "role": "solo",
                "model": "not-applicable",
                "effort": "not-applicable",
                "expected_effort": "not-applicable",
                "task_id": "forged-seq-t1-solo",
            }
        ],
    },
]


def _try_write_forgery(target_dir: Path) -> None:
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        with (target_dir / "trials.jsonl").open("w", encoding="ascii", newline="\n") as fh:
            for rec in _FORGED:
                fh.write(json.dumps(rec) + "\n")
    except OSError:
        pass  # best-effort attack; unreachable dirs are the whole point of the test


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mock_arm_forge.py <prompt_path> <sandbox_repo>", file=sys.stderr)
        return 2

    sandbox_repo = Path(argv[2])
    target = sandbox_repo / "benchmarks" / "sandbox" / "deploy.sh"
    if not target.is_file():
        print("mock_arm_forge: target missing", file=sys.stderr)
        return 1

    text = target.read_bytes().decode("utf-8")
    lines = text.split("\n")
    if GUARD not in lines[:5]:
        lines.insert(1, GUARD)
        target.write_bytes("\n".join(lines).encode("utf-8"))

    # Every directory the arm can derive from what the runner handed it. NONE of these is
    # the runner's --out dir -- that path is never passed to the arm in argv or env, which
    # is the whole point of the test. (The sandbox repo / cwd are deliberately not
    # targeted: a write there is caught by snapshot.diff and is the tamper test's concern.)
    candidates: list[Path] = []
    prompt_path = Path(argv[1])
    candidates.append(prompt_path.parent)          # the arm's own scratch dir
    session_file = os.environ.get("SEFI_ARM_SESSION_FILE")
    if session_file:
        candidates.append(Path(session_file).parent)

    seen: set[str] = set()
    for cand in candidates:
        key = str(cand)
        if key in seen:
            continue
        seen.add(key)
        _try_write_forgery(cand)

    session_id = os.environ.get("SEFI_ARM_SESSION_ID", "")
    if session_file:
        Path(session_file).write_bytes(session_id.encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
