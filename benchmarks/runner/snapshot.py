"""Out-of-process filesystem snapshot + diff for benchmark trial integrity.

The runner process -- never an arm -- reads the sandbox tree and records a content
manifest. Binary-mode hashing plus the forced ``eol=lf`` checkout from ``sandbox.py``
makes the manifest byte-reproducible on this Windows host. The caller writes manifests
to ``benchmarks/results/<run-id>/``, OUTSIDE the sandbox, in a runner-owned dir the
arm's prompt and cwd never name.

Standard library only: hashlib, os, pathlib.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path


def snapshot(repo_path: str | os.PathLike[str]) -> dict[str, str]:
    """Map every file under ``repo_path`` (EXCLUDING ``.git``) to ``sha256`` of its bytes.

    Keys are POSIX-style forward-slash relpaths, sorted, so the manifest is stable across
    operating systems and across independent walks of the same tree.
    """
    root = Path(repo_path)
    manifest: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune ``.git`` at any depth; also keep the walk order deterministic.
        if ".git" in dirnames:
            dirnames.remove(".git")
        dirnames.sort()
        for name in sorted(filenames):
            path = Path(dirpath) / name
            rel = path.relative_to(root).as_posix()
            with open(path, "rb") as handle:
                manifest[rel] = hashlib.sha256(handle.read()).hexdigest()
    return dict(sorted(manifest.items()))


def _normalize_allowed(allowed_paths: list[str]) -> list[str]:
    return [entry.replace(os.sep, "/").strip("/") for entry in allowed_paths if entry]


def diff(
    before: dict[str, str],
    after: dict[str, str],
    allowed_paths: list[str],
) -> list[str]:
    """Sorted list of every path that changed / was added / was removed AND is not under
    any entry of ``allowed_paths``.

    An ``allowed_paths`` entry matches a path exactly or as a directory prefix
    (``a/b`` covers ``a/b`` and ``a/b/c`` but not ``a/bc``).
    """
    allowed = _normalize_allowed(allowed_paths)

    def is_allowed(path: str) -> bool:
        return any(path == a or path.startswith(a + "/") for a in allowed)

    touched: set[str] = set()
    for path, digest in after.items():
        if before.get(path) != digest:
            touched.add(path)
    for path in before:
        if path not in after:
            touched.add(path)
    return sorted(path for path in touched if not is_allowed(path))
