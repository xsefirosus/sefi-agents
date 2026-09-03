#!/usr/bin/env python3
"""Test-only mock arm that sleeps well past any sane trial timeout.

Exercises ``benchmarks/runner/arms.run_arm``'s ``subprocess.TimeoutExpired`` -> non-fatal
``ArmResult(exit_code != 0)`` path. No network, no model call, ASCII only.

Standard library only: time.
"""

from __future__ import annotations

import time


def main() -> int:
    time.sleep(30)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
