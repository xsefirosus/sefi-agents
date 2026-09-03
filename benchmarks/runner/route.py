"""Out-of-process route-evidence collector for benchmark trial integrity.

``capture_route()`` shells out to ``check-route.sh`` -- the security-reviewed route-evidence
shim on ``feat/route-evidence-live`` @ ``8c1779c`` -- and maps its exit code + one JSON
stdout line to a single boolean, ``RouteResult.captured``. That boolean is the ONLY route
input to ``integrity.verify`` (step 6): no arm-written value ever reaches scoring.

Resolution order for the script:
  1. the explicit test-only ``check_route_cmd`` argument (a fixture shell script);
  2. else ``<repo-root>/plugins/sefi-core/scripts/check-route.sh``.
``check-route.sh`` is NOT on this branch (see the plan's "Ordering dependency" risk), so
the default path is normally ABSENT here -- that resolves to ``captured is False``
(fail-closed), never an exception. There is deliberately NO env-var override: the
Phase-3 security review rejected exactly that pattern. Real operators never pass
``check_route_cmd``.

Invocation: ``check-route.sh <harness> <tier> <session-record-or-thread-id>`` -- the 3rd
positional is a lowercase-UUID thread id or ``-`` (NOT a file path), so ``None`` is
passed as ``-``.

CAPTURED (the check passes):
  * exit 0 with status ``match`` or ``not-applicable``;
  * exit 1 with status ``mismatch`` or ``unavailable``.
``unavailable`` (claude-code, unconditional) and ``not-applicable`` (a flexible tier)
STILL count as captured -- the trial stays scoreable while the separate route-correctness
axis honestly reports ``model=unchecked``.

NOT CAPTURED (the check fails, fail-closed):
  * exit 2 (usage); exit 3 (no interpreter / shim reports skipped);
  * exit 1 with status ``invalid``;
  * ANY missing / non-JSON / unparseable stdout line;
  * the script file absent;
  * a raised ``OSError`` / ``TimeoutExpired``.

Standard library only: json, os, subprocess, pathlib, typing.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import NamedTuple

# check-route.sh is a subprocess that resolves its own Python interpreter; give it room
# but never let a hung shim hang a benchmark run.
_TIMEOUT_S = 60

_CAPTURED_ON_0 = ("match", "not-applicable")
_CAPTURED_ON_1 = ("mismatch", "unavailable")


class RouteResult(NamedTuple):
    captured: bool
    status: str | None
    reason: str | None
    expected_model: str | None
    expected_effort: str | None
    observed_model: str | None
    observed_effort: str | None
    exit_code: int | None


def _result(captured: bool, exit_code: int | None, obj: dict | None) -> RouteResult:
    obj = obj or {}
    return RouteResult(
        captured=captured,
        status=obj.get("status"),
        reason=obj.get("reason"),
        expected_model=obj.get("expected_model"),
        expected_effort=obj.get("expected_effort"),
        observed_model=obj.get("observed_model"),
        observed_effort=obj.get("observed_effort"),
        exit_code=exit_code,
    )


def _resolve_script(check_route_cmd: str | os.PathLike[str] | None) -> Path:
    if check_route_cmd is not None:
        return Path(check_route_cmd)
    root = Path(__file__).resolve().parents[2]
    return root / "plugins" / "sefi-core" / "scripts" / "check-route.sh"


def _resolve_bash() -> str | None:
    """Absolute path to a real bash by an explicit validated PATH walk.

    A bare ``bash`` on Windows is resolved by CreateProcess (System32 first -> WSL relay
    stub). Mirrors ``check-route.py`` ``resolve_bash`` -- and, as there, NO env override.
    """
    names = ("bash.exe", "bash") if os.name == "nt" else ("bash",)
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    return None


def _parse_line(stdout: str) -> dict | None:
    """The single JSON object line ``check-route.py`` prints on stdout, or None."""
    lines = [ln for ln in stdout.splitlines() if ln.strip()]
    if not lines:
        return None
    try:
        obj = json.loads(lines[-1])
    except (ValueError, TypeError):
        return None
    return obj if isinstance(obj, dict) else None


def capture_route(
    harness: str,
    tier: str,
    session_record_ref: str | None,
    check_route_cmd: str | os.PathLike[str] | None = None,
) -> RouteResult:
    """Collect route evidence out-of-process. See module docstring for the full matrix."""
    script = _resolve_script(check_route_cmd)
    if not script.is_file():
        # check-route.sh absent -> fail-closed, never an exception.
        return _result(False, None, None)

    bash = _resolve_bash()
    if bash is None:
        return _result(False, None, None)

    ref = session_record_ref if session_record_ref else "-"
    cmd = [bash, str(script), str(harness), str(tier), str(ref)]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_S,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return _result(False, None, None)

    obj = _parse_line(proc.stdout)
    if obj is None:
        # Missing / non-JSON / unparseable stdout line -> NOT captured, any exit code.
        return _result(False, proc.returncode, None)

    status = obj.get("status")
    rc = proc.returncode
    captured = (rc == 0 and status in _CAPTURED_ON_0) or (
        rc == 1 and status in _CAPTURED_ON_1
    )
    return _result(captured, rc, obj)
