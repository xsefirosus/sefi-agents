#!/usr/bin/env python3
"""Test-only mock arm: does the ``sh-strict-mode`` task but echoes a DIFFERENT
lowercase-UUID into ``SEFI_ARM_SESSION_FILE`` instead of the runner-generated id.

Proves ``arms.run_arm`` fails closed: an echoed value that does not byte-equal the
runner's ``SEFI_ARM_SESSION_ID`` yields ``ArmResult.session_record_ref is None`` (route
not captured -> trial excluded). The arm does not get to choose the session ref.

No network, no model call, ASCII only. Invoked as::

    <python> mock_arm_wrongsession.py <prompt_path> <sandbox_repo>

Standard library only: os, sys, pathlib.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

GUARD = "set -euo pipefail"
# A fixed, valid lowercase 8-4-4-4-12 UUID that is NOT the runner's generated id.
WRONG_ID = "deadbeef-0000-4000-8000-000000000000"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mock_arm_wrongsession.py <prompt_path> <sandbox_repo>", file=sys.stderr)
        return 2

    sandbox_repo = Path(argv[2])
    target = sandbox_repo / "benchmarks" / "sandbox" / "deploy.sh"
    if not target.is_file():
        print("mock_arm_wrongsession: target missing", file=sys.stderr)
        return 1

    text = target.read_bytes().decode("utf-8")
    lines = text.split("\n")
    if GUARD not in lines[:5]:
        lines.insert(1, GUARD)
        target.write_bytes("\n".join(lines).encode("utf-8"))

    session_file = os.environ.get("SEFI_ARM_SESSION_FILE")
    if session_file:
        Path(session_file).write_bytes(WRONG_ID.encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
