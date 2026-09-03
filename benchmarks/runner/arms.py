"""Arm invocation for out-of-process benchmark trials.

``run_arm()`` launches ONE arm (``control`` / ``sefi-chain`` / ``sefi-chain-sequential``)
for one harness, with its cwd INSIDE the sandbox clone, under a hard subprocess timeout.
It returns an ``ArmResult`` of RUNNER-OBSERVED values only:

  * ``exit_code``           -- the arm process return code. Non-zero on timeout or a
                               missing harness binary; ``run_arm`` never raises for those.
  * ``wall_time_s``         -- monotonic wall clock, ``float >= 0``.
  * ``session_record_ref``  -- the harness's OWN session / thread id, captured by the
                               RUNNER from the invocation: the runner generates the id,
                               exports it in the child environment, and reads it back from
                               a known file the harness echoes it into. It is NEVER parsed
                               from arm stdout, and it is returned ONLY when the echoed
                               value byte-equals the runner-generated id -- a missing /
                               blank / different echo yields ``None`` (route-not-captured
                               -> the trial fails closed).
  * ``raw_log_path``        -- combined stdout+stderr saved to a file for humans. It is
                               written into a private per-arm scratch dir first; the
                               RUNNER copies it under ``results_dir`` AFTER the arm process
                               has exited, so the arm never learns the results-dir path.
                               ``record.py`` (step 6) never reads it.

Trust boundary: ALL arm-facing scratch (the prompt file, the session-echo file, the raw
log) is created in a private ``tempfile.mkdtemp(prefix="sefi-arm-")`` dir torn down in a
``finally:``; the runner never puts that dir -- or ``results_dir`` (which holds
``trials.jsonl``) -- on the child's argv or env, and the sandbox clone's ``origin`` remote
is stripped before the arm runs. With no OS-level isolation, an arm running as the same
user is NOT *prevented* from locating ``benchmarks/results/`` by other means (a well-known
path, a later cwd), so the guarantee is precisely: no arm-written VALUE is a scoring
input; ``run.py``'s finalize step refuses to replace an existing ``trials.jsonl``; every
abort unlinks a raced-in ``trials.jsonl``. Wholesale post-exit artifact forgery is out of
scope without a container.

The test-only ``mock_arm`` seam runs a local Python file via ``resolve_python()`` instead
of a real harness CLI; EVERY test in ``benchmarks/test_runner.py`` uses it. The
real-harness command builder (``_real_command``) is best-effort and UNKNOWN-marked: no
test exercises it, and ``codex`` / ``opencode`` presence on this host is UNKNOWN and not
required.

Standard library only: os, re, shutil, subprocess, tempfile, time, pathlib, typing.
Teardown (``_rmtree``) is the shared helper in ``benchmarks/runner/_fsutil.py``.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import NamedTuple

from benchmarks.runner._fsutil import _rmtree
from benchmarks.runner.sandbox import resolve_python

_STRATEGIES = ("control", "sefi-chain", "sefi-chain-sequential")
_HARNESSES = ("claude-code", "codex", "opencode")

# Conventional "timed out" code (GNU ``timeout`` uses 124); "command not found" is 127.
# Either way the trial is non-fatal here and simply scores nothing downstream.
_TIMEOUT_EXIT = 124
_NO_BINARY_EXIT = 127


class ArmResult(NamedTuple):
    exit_code: int
    wall_time_s: float
    session_record_ref: str | None
    raw_log_path: str


def _new_session_id() -> str:
    """A fresh lowercase UUIDv4-shaped id.

    ``os.urandom`` so we pull in no extra module; the shape (lowercase 8-4-4-4-12 hex) is
    exactly what ``check-route.sh`` / ``check-route.py`` validate for their 3rd positional
    (``UUID_RE`` on ``feat/route-evidence-live``). This id is the runner's handle on the
    invocation, never a value the arm chose.
    """
    b = bytearray(os.urandom(16))
    b[6] = (b[6] & 0x0F) | 0x40
    b[8] = (b[8] & 0x3F) | 0x80
    h = b.hex()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def _which(names: tuple[str, ...]) -> str | None:
    """First entry in PATH that is a regular file and executable, or None.

    A bare name handed to subprocess on Windows is resolved by CreateProcess (System32
    first -> WSL relay stub hazard); walking PATH ourselves returns the real binary.
    Mirrors ``sandbox._walk_path`` / ``check-route.py`` ``resolve_bash``.
    """
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    return None


# A drive-letter root (``C:\`` / ``C:/``) or a POSIX root (``/``). A pure-string test --
# ``Path(...).is_absolute()`` alone misses ``/home/u/x`` on Windows.
_ABS_LOOKING_RE = re.compile(r"^([A-Za-z]:[\\/]|/)")


def _redact_arg(arg: str) -> str:
    """Reduce one logged command-line arg to something free of operator-identifying paths.

    An arg that is an existing path, or merely *looks* absolute (drive-letter / POSIX
    root), collapses to its basename -- the scratch-dir prefix embeds the operator's home
    dir (a ``C:\\Users`` / ``home`` / ``Users`` rooted path). A remaining arg that is a
    real prompt STRING (not a path) is kept as-is except that a leading ``Path.home()``
    prefix is rewritten to ``~``. Net: no home-dir substring reaches the copied raw log.
    """
    if _ABS_LOOKING_RE.match(arg):
        return Path(arg).name
    try:
        if Path(arg).is_absolute() or Path(arg).exists():
            return Path(arg).name
    except (OSError, ValueError):
        pass
    home = str(Path.home())
    if home and arg.startswith(home):
        return "~" + arg[len(home):]
    return arg


def _redact_text(s: str) -> str:
    """Rewrite every occurrence of the operator's home dir -- native-separator form AND
    forward-slash form -- to ``~``.

    ``_redact_arg`` (above) handles one command-line arg at a time; this handles
    free-form captured output: arm stdout / stderr before they enter the raw-log body
    (``arms.py``) and the fatal-abort reason string before it enters ``ABORTED.md``
    (``run.py`` imports this). Net: no home-dir substring reaches a results-dir file.
    """
    home = str(Path.home())
    if not home:
        return s
    out = s.replace(home, "~")
    home_fwd = home.replace("\\", "/")
    if home_fwd != home:
        out = out.replace(home_fwd, "~")
    return out


def _real_command(strategy: str, harness: str, prompt_text: str) -> list[str]:
    """Best-effort real-harness command. NO test exercises this path -- every acceptance
    uses the ``mock_arm`` seam. Details not verifiable on this dev host are marked UNKNOWN.
    """
    if harness == "claude-code":
        # UNKNOWN: the exact headless flag surface of the installed ``claude`` binary.
        # Best guess per harness-actions.md "Invoke the harness headless".
        base = [_which(("claude.exe", "claude")) or "claude", "-p", prompt_text]
    elif harness == "codex":
        # UNKNOWN: whether ``codex`` is installed on this host at all; NOT required.
        base = [_which(("codex.exe", "codex")) or "codex", "exec", prompt_text]
    elif harness == "opencode":
        # UNKNOWN: whether ``opencode`` is installed on this host at all; NOT required.
        base = [_which(("opencode.exe", "opencode")) or "opencode", "run", prompt_text]
    else:  # pragma: no cover - run_arm validates harness before calling this
        raise ValueError(f"unknown harness: {harness!r}")

    # Dispatch-asymmetry rule (benchmarks/README.md:285-288): ``sefi-chain`` is real
    # PARALLEL dispatch; ``sefi-chain-sequential`` is the roster run SEQUENTIALLY in one
    # context. The two are NEVER equated -- distinct branches / distinct invocation here,
    # even though the real flag names are UNKNOWN on this host.
    if strategy == "control":
        return base
    if strategy == "sefi-chain":
        return [*base, "--sefi-dispatch", "parallel"]  # UNKNOWN flag name
    # sefi-chain-sequential
    return [*base, "--sefi-dispatch", "sequential"]  # UNKNOWN flag name


def run_arm(
    strategy: str,
    harness: str,
    prompt_text: str,
    sandbox_repo: str | os.PathLike[str],
    timeout_s: float,
    *,
    mock_arm: str | os.PathLike[str] | None = None,
    results_dir: str | os.PathLike[str] | None = None,
) -> ArmResult:
    """Run one arm and return runner-observed facts about it. See module docstring.

    ``prompt_text`` is passed in verbatim by the caller (which read the case
    ``prompt_file``); ``run_arm`` does NOT read ``cases.json``. A ``subprocess.TimeoutExpired``
    or a missing harness binary (``OSError``) is caught and returned as a NON-FATAL
    ``ArmResult`` with a non-zero ``exit_code`` -- never raised out of ``run_arm``.
    """
    if strategy not in _STRATEGIES:
        raise ValueError(f"strategy must be one of {_STRATEGIES}, got {strategy!r}")
    if harness not in _HARNESSES:
        raise ValueError(f"harness must be one of {_HARNESSES}, got {harness!r}")

    repo = Path(sandbox_repo)
    if not repo.is_dir():
        raise ValueError(f"sandbox_repo is not a directory: {repo}")

    # ALL arm-facing scratch lives in a private dir, NEVER results_dir. Torn down in the
    # finally: below. The arm is never handed the results-dir path in argv or env.
    arm_scratch = Path(tempfile.mkdtemp(prefix="sefi-arm-"))
    try:
        session_id = _new_session_id()
        session_file = arm_scratch / f"arm-session-{session_id}.txt"
        prompt_path = arm_scratch / f"arm-prompt-{session_id}.md"
        prompt_path.write_text(prompt_text, encoding="utf-8")
        raw_log_path = arm_scratch / f"arm-{strategy}-{session_id}.log"

        # The runner sets the session id in the child environment; the harness (or the
        # mock) echoes it into SEFI_ARM_SESSION_FILE (in the private scratch dir). The
        # runner reads THAT file back -- it never trusts arm stdout for the id.
        env = os.environ.copy()
        env["SEFI_ARM_SESSION_ID"] = session_id
        env["SEFI_ARM_SESSION_FILE"] = str(session_file)
        env["SEFI_ARM_STRATEGY"] = strategy
        env["SEFI_ARM_HARNESS"] = harness

        if mock_arm is not None:
            cmd = [
                resolve_python(),
                str(Path(mock_arm).resolve(strict=True)),
                str(prompt_path),
                repo.as_posix(),
            ]
        else:
            cmd = _real_command(strategy, harness, prompt_text)

        start = time.monotonic()
        stdout = ""
        stderr = ""
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(repo),
                env=env,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
            exit_code = proc.returncode
            stdout = proc.stdout or ""
            stderr = proc.stderr or ""
        except subprocess.TimeoutExpired as exc:
            # NON-FATAL: a timed-out arm is a recorded result, not a raised exception.
            exit_code = _TIMEOUT_EXIT
            stdout = _as_text(exc.stdout)
            stderr = _as_text(exc.stderr)
            stderr += f"\n[run_arm] subprocess.TimeoutExpired after {timeout_s}s\n"
        except OSError as exc:
            # NON-FATAL: no usable harness binary -> fail-closed (plan objective:24-27).
            exit_code = _NO_BINARY_EXIT
            stderr = f"[run_arm] could not launch arm: {exc}\n"
        wall_time_s = max(0.0, time.monotonic() - start)

        # Redact operator-identifying paths from the logged command line: cmd[0] (the
        # interpreter / binary) -> basename; every remaining arg through _redact_arg
        # (basename for a path / absolute-looking arg, ``~`` for a home-prefixed string).
        # benchmarks/README.md stance on personal paths.
        logged_cmd = (
            [Path(cmd[0]).name, *(_redact_arg(a) for a in cmd[1:])] if cmd else []
        )
        # F-B / qa-Minor-1: stdout/stderr are copied verbatim under results_dir, so a
        # home path an arm prints must be redacted to ``~`` before it enters the log body.
        raw_log_path.write_text(
            f"$ {' '.join(logged_cmd)}\n--- stdout ---\n"
            f"{_redact_text(stdout)}\n--- stderr ---\n{_redact_text(stderr)}\n",
            encoding="utf-8",
        )

        # The id is trusted ONLY when the echoed value byte-equals the id the runner
        # generated. A missing / blank / different echo -> None -> route not captured ->
        # the trial fails closed. The arm cannot supply a session ref of its choosing.
        session_record_ref: str | None = None
        try:
            if session_file.is_file():
                echoed = session_file.read_text(encoding="utf-8", errors="replace").strip()
                session_record_ref = session_id if echoed == session_id else None
        except OSError:
            session_record_ref = None

        # The RUNNER -- after the arm has exited -- copies the human-readable log under
        # results_dir. The arm never had that path.
        final_log_path = str(raw_log_path)
        if results_dir is not None:
            dest_dir = Path(results_dir)
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / raw_log_path.name
            shutil.copyfile(raw_log_path, dest)
            final_log_path = str(dest)

        return ArmResult(
            exit_code=exit_code,
            wall_time_s=float(wall_time_s),
            session_record_ref=session_record_ref,
            raw_log_path=final_log_path,
        )
    finally:
        # Same read-only-retry teardown sandbox.py uses (shared _fsutil._rmtree):
        # ignore_errors=False, so a genuine failure to clear the arm scratch surfaces
        # instead of being silently swallowed.
        _rmtree(arm_scratch)


def _as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value
