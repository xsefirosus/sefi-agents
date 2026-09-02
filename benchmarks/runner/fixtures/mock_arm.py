#!/usr/bin/env python3
"""Test-only mock arm: performs the ``sh-strict-mode`` benchmark case inside the sandbox.

No network, no model call, ASCII only. Invoked by ``benchmarks/runner/arms.run_arm`` via
the ``mock_arm`` seam as::

    <python> mock_arm.py <prompt_path> <sandbox_repo>

It makes ``benchmarks/cases/check_sh-strict-mode.sh`` pass against the sandbox copy of
``benchmarks/sandbox/deploy.sh`` (inserts the exact line ``set -euo pipefail`` right after
the shebang if it is not already within the first five lines), and echoes the runner's
session id into ``SEFI_ARM_SESSION_FILE`` so the runner can capture it. It prints nothing
that any scoring code reads.

Standard library only: os, sys, pathlib.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

GUARD = "set -euo pipefail"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mock_arm.py <prompt_path> <sandbox_repo>", file=sys.stderr)
        return 2

    sandbox_repo = Path(argv[2])
    target = sandbox_repo / "benchmarks" / "sandbox" / "deploy.sh"
    if not target.is_file():
        print(f"mock_arm: target missing: {target}", file=sys.stderr)
        return 1

    # Read/write bytes with explicit LF joins: text-mode writes on Windows would emit
    # CRLF, which breaks the check's `grep -qx 'set -euo pipefail'` (the trailing \r
    # defeats the whole-line match) and the reproducible-manifest guarantee.
    text = target.read_bytes().decode("utf-8")
    lines = text.split("\n")
    if GUARD not in lines[:5]:
        lines.insert(1, GUARD)
        target.write_bytes("\n".join(lines).encode("utf-8"))

    session_file = os.environ.get("SEFI_ARM_SESSION_FILE")
    session_id = os.environ.get("SEFI_ARM_SESSION_ID", "")
    if session_file:
        Path(session_file).write_bytes(session_id.encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
