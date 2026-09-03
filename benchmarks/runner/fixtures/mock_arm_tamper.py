#!/usr/bin/env python3
"""Test-only mock arm: does the ``sh-strict-mode`` task AND tampers a file OUTSIDE the
case's ``allowed_paths``.

Task behaviour is identical to ``mock_arm.py`` (inserts the exact line
``set -euo pipefail`` right after the shebang), so the pristine acceptance check still
passes -- but this mock ALSO mutates ``benchmarks/cases.json`` inside the sandbox, a path
NOT under the ``sh-strict-mode`` case's ``allowed_paths``
(``benchmarks/sandbox/deploy.sh``). ``snapshot.diff`` then flags ``benchmarks/cases.json``
and ``integrity.verify`` returns ``False``, so ``record.py`` omits ``integrity_ok`` and
``scorecard.py`` excludes the trial. Used by ``benchmarks/test_runner.py`` EndToEndTests
to prove a tampered trial is excluded.

No network, no model call, ASCII only, relative paths only. Invoked by
``benchmarks/runner/arms.run_arm`` via the ``mock_arm`` seam as::

    <python> mock_arm_tamper.py <prompt_path> <sandbox_repo>

Standard library only: os, sys, pathlib.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

GUARD = "set -euo pipefail"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mock_arm_tamper.py <prompt_path> <sandbox_repo>", file=sys.stderr)
        return 2

    sandbox_repo = Path(argv[2])
    target = sandbox_repo / "benchmarks" / "sandbox" / "deploy.sh"
    if not target.is_file():
        print(f"mock_arm_tamper: target missing: {target}", file=sys.stderr)
        return 1

    # Do the real task (byte-level LF writes, same as mock_arm.py).
    text = target.read_bytes().decode("utf-8")
    lines = text.split("\n")
    if GUARD not in lines[:5]:
        lines.insert(1, GUARD)
        target.write_bytes("\n".join(lines).encode("utf-8"))

    # TAMPER: mutate a tracked file OUTSIDE the case's allowed_paths. A trailing newline
    # is enough to change the sha256 that snapshot.snapshot() records.
    tamper = sandbox_repo / "benchmarks" / "cases.json"
    if tamper.is_file():
        tamper.write_bytes(tamper.read_bytes() + b"\n")

    session_file = os.environ.get("SEFI_ARM_SESSION_FILE")
    session_id = os.environ.get("SEFI_ARM_SESSION_ID", "")
    if session_file:
        Path(session_file).write_bytes(session_id.encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
