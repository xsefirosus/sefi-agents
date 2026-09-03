#!/usr/bin/env python3
"""Test-only mock arm: prints the operator's home directory (native AND forward-slash
form) to stdout so ``benchmarks/runner/arms._redact_text`` can be exercised -- the copied
raw log must show ``~``, never the home path (F-B / qa-Minor-1).

It does NOT perform the case task; the redaction test only inspects the raw log. It still
echoes the runner's session id into ``SEFI_ARM_SESSION_FILE`` so ``run_arm`` behaves
normally. No network, no model call, ASCII only, NO personal-path literal -- the home dir
is computed at runtime.

Invoked by ``benchmarks/runner/arms.run_arm`` via the ``mock_arm`` seam as::

    <python> mock_arm_homeleak.py <prompt_path> <sandbox_repo>

Standard library only: os, sys, pathlib.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mock_arm_homeleak.py <prompt_path> <sandbox_repo>", file=sys.stderr)
        return 2

    home = str(Path.home())
    home_fwd = home.replace("\\", "/")
    print(f"wrote report to {home}/report.txt")
    print(f"posix form: {home_fwd}/report.txt", file=sys.stderr)

    session_file = os.environ.get("SEFI_ARM_SESSION_FILE")
    session_id = os.environ.get("SEFI_ARM_SESSION_ID", "")
    if session_file:
        Path(session_file).write_bytes(session_id.encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
