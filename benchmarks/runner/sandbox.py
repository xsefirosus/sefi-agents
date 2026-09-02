"""Filesystem sandbox builder for out-of-process benchmark trials.

A trial runs inside a real ``git clone`` at a pinned ref -- its OWN object store, never
a ``git worktree`` (the withdrawn design's root failure: a worktree shares ``.git``,
``info/exclude``, hooks, and config with the origin). The scratch dir lives OUTSIDE any
repo tree via ``tempfile.mkdtemp`` and is removed in a ``finally:`` so teardown runs on
error and timeout too.

External tools are resolved by an explicit validated PATH walk (isfile + X_OK), never a
bare name handed to subprocess: on Windows a bare ``git`` / ``bash`` is resolved by
CreateProcess, which searches System32 first and can hit a WSL relay stub. Mirrors
``plugins/sefi-core/scripts/check-route.py`` ``resolve_bash``.

Standard library only: subprocess, shutil, tempfile, os, pathlib, contextlib.
"""

from __future__ import annotations

import contextlib
import os
import shutil
import stat
import subprocess
import tempfile
from collections.abc import Iterator
from pathlib import Path


def _force_remove(func, path, _exc_info):  # type: ignore[no-untyped-def]
    """rmtree onerror hook: git marks pack files read-only, and Windows then refuses the
    unlink with WinError 5. Clear the read-only bit and retry once. Not ``ignore_errors``
    -- a genuine failure still propagates -- teardown must actually complete on this host.
    """
    os.chmod(path, stat.S_IWRITE)
    func(path)


def _walk_path(names: tuple[str, ...]) -> str | None:
    """First entry in PATH that is a regular file and executable, or None."""
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    return None


def resolve_git() -> str:
    """Absolute path to a real ``git``, found by walking PATH ourselves."""
    names = ("git", "git.exe") if os.name == "nt" else ("git",)
    found = _walk_path(names)
    if found is None:
        raise RuntimeError("git not found on PATH (validated isfile + X_OK walk)")
    return found


def resolve_python() -> str:
    """Absolute path to a working interpreter: try ``python3`` first, then ``python``.

    This host's ``python3`` is the broken Microsoft Store stub, so a candidate is
    accepted only if ``<candidate> --version`` actually exits 0.
    """
    if os.name == "nt":
        groups = (("python3.exe", "python3"), ("python.exe", "python"))
    else:
        groups = (("python3",), ("python",))
    for names in groups:
        candidate = _walk_path(names)
        if candidate is None:
            continue
        try:
            proc = subprocess.run(
                [candidate, "--version"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
        except OSError:
            continue
        if proc.returncode == 0:
            return candidate
    raise RuntimeError("no working python3/python found on PATH")


@contextlib.contextmanager
def sandbox(origin_repo: str | os.PathLike[str], pinned_ref: str) -> Iterator[Path]:
    """Yield a fresh ``git clone`` of ``origin_repo`` checked out at ``pinned_ref``.

    (a) scratch dir via ``tempfile.mkdtemp(prefix="sefi-bench-")``, OUTSIDE any repo tree
        and outside ``benchmarks/results/``;
    (b) ``git clone --no-checkout --no-hardlinks --no-local <file-uri> <scratch>/repo``
        -- its own object store, NEVER ``git worktree``. ``--no-checkout`` is load-bearing:
        it makes the forced checkout in (c) the ONLY checkout, so the system
        ``core.autocrlf=true`` never gets a chance to CRLF-convert the tree first (that
        first, uncontrolled checkout was a real source of a non-reproducible manifest);
    (c) write ``<scratch>/repo/.gitattributes`` with ``* -text`` BEFORE checkout, then
        ``git -C <repo> -c core.autocrlf=false -c core.eol=lf checkout --force
        <pinned_ref> -- .`` (detached), so a system ``core.autocrlf=true`` cannot rewrite
        content on checkout;
    (d) yield the repo path;
    (e) ``finally:`` ``shutil.rmtree(<scratch>, ignore_errors=False)`` -- teardown runs
        on error/timeout too.
    """
    git = resolve_git()
    origin_abs = Path(origin_repo).resolve(strict=True)
    # A proper ``file://`` URI (three-slash, percent-encoded) is what git accepts on both
    # Windows (``file:///D:/repo``) and POSIX (``file:///home/u/repo``); combined with
    # ``--no-local`` it forces real transport, so the clone gets its own object store and
    # writes no ``objects/info/alternates``.
    origin_uri = origin_abs.as_uri()

    scratch = Path(tempfile.mkdtemp(prefix="sefi-bench-"))
    try:
        repo = scratch / "repo"
        subprocess.run(
            [
                git,
                "clone",
                "--no-checkout",
                "--no-hardlinks",
                "--no-local",
                origin_uri,
                str(repo),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        (repo / ".gitattributes").write_text("* -text\n", encoding="ascii")
        subprocess.run(
            [
                git,
                "-C",
                str(repo),
                "-c",
                "core.autocrlf=false",
                "-c",
                "core.eol=lf",
                "checkout",
                "--force",
                pinned_ref,
                "--",
                ".",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        yield repo
    finally:
        shutil.rmtree(scratch, ignore_errors=False, onerror=_force_remove)
