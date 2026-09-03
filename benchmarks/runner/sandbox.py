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

Standard library only: subprocess, tempfile, os, pathlib, contextlib. Teardown
(``_rmtree``) is the shared helper in ``benchmarks/runner/_fsutil.py``.
"""

from __future__ import annotations

import contextlib
import os
import subprocess
import tempfile
from collections.abc import Iterator
from pathlib import Path

from benchmarks.runner._fsutil import _rmtree


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
    (b) ``git clone -c core.logallrefupdates=false --no-checkout --no-hardlinks
        --no-local <file-uri> <scratch>/repo`` -- its own object store, NEVER
        ``git worktree``. ``--no-checkout`` is load-bearing: it makes the forced checkout
        in (c) the ONLY checkout, so the system ``core.autocrlf=true`` never gets a chance
        to CRLF-convert the tree first (that first, uncontrolled checkout was a real
        source of a non-reproducible manifest). ``core.logallrefupdates=false`` stops the
        clone from writing ``<repo>/.git/logs/HEAD`` -- whose ``clone: from
        file:///D:/...`` line would otherwise disclose the operator's absolute repo path
        (F-A / NEW-1);
    (c) write ``<scratch>/repo/.gitattributes`` with ``* -text`` BEFORE checkout, then
        ``git -C <repo> -c core.autocrlf=false -c core.eol=lf checkout --force
        <pinned_ref> -- .``, so a system ``core.autocrlf=true`` cannot rewrite content on
        checkout;
    (d) ``git -C <repo> -c core.logallrefupdates=false checkout --detach <pinned_ref>`` --
        so ``<repo>/.git/HEAD`` holds a bare SHA, not ``ref: refs/heads/<origin branch>``
        (the origin's branch name is an operator fingerprint too), and again no reflog;
    (e) ``git -C <repo> remote remove origin`` -- the last record of the operator's
        absolute origin path (``url = file:///D:/...``) and origin branch name in
        ``<repo>/.git/config``. Then physically drop ``<repo>/.git/logs`` if anything
        recreated it -- the runner needs no reflog;
    (f) yield the repo path;
    (g) ``finally:`` ``_rmtree(<scratch>)`` (``ignore_errors=False``) -- teardown runs on
        error/timeout too.
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
                # F-A / NEW-1: no clone reflog. Without this, ``<repo>/.git/logs/HEAD``
                # and ``.git/logs/refs/heads/<origin branch>`` each carry a
                # ``clone: from file:///D:/...`` line -- the operator's absolute repo
                # path, disclosed by ``cat .git/logs/HEAD`` from the arm's cwd. The
                # runner only does checkout / config / remote-remove / a filesystem
                # snapshot; it never reads a reflog.
                "-c",
                "core.logallrefupdates=false",
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
        # Detach HEAD onto the pinned commit so ``<repo>/.git/HEAD`` holds a bare SHA
        # rather than ``ref: refs/heads/feat/benchmark-runner`` -- the origin's branch
        # name is as much an operator fingerprint as its path. ``core.logallrefupdates
        # =false`` again so the detach writes no ``.git/logs/HEAD``.
        subprocess.run(
            [
                git,
                "-C",
                str(repo),
                "-c",
                "core.logallrefupdates=false",
                "checkout",
                "--detach",
                pinned_ref,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        # Strip the ``origin`` remote BEFORE the arm can see the tree: it is the last
        # place ``<repo>/.git/config`` records ``url = file:///D:/...`` (and a
        # ``[branch "feat/benchmark-runner"]`` section). The clone has its own object
        # store (``--no-local``), so removing the remote loses nothing the runner needs.
        subprocess.run(
            [git, "-C", str(repo), "remote", "remove", "origin"],
            capture_output=True,
            text=True,
            check=True,
        )
        # Defense in depth: both git calls above ran with ``core.logallrefupdates=false``,
        # but physically drop any reflog dir a future git / code path might still create.
        # The runner needs no reflog; git regenerates ``logs/`` lazily if ever required.
        logs_dir = repo / ".git" / "logs"
        if logs_dir.exists():
            _rmtree(logs_dir)
        yield repo
    finally:
        _rmtree(scratch)
