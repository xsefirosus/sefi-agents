"""Shared filesystem teardown helper for the out-of-process benchmark runner.

``_rmtree`` is ``shutil.rmtree`` with a read-only-retry hook on whichever hook API the
running Python supports (``onexc`` >= 3.12, ``onerror`` 3.11). git marks pack files
read-only and Windows then refuses the unlink with WinError 5; the hook clears the
read-only bit and retries once. ``ignore_errors=False`` either way -- teardown must
actually complete on this host, and a genuine second failure still propagates.

Lifted verbatim from ``sandbox.py`` so ``sandbox.py`` and ``arms.py`` share ONE
implementation instead of one raising copy and one silent ``ignore_errors=True`` copy.

Standard library only: os, shutil, stat, sys.
"""

from __future__ import annotations

import os
import shutil
import stat
import sys


def _chmod_and_retry(func, path) -> None:
    """git marks pack files read-only, and Windows then refuses the unlink with WinError
    5. Clear the read-only bit and retry once. A genuine second failure still propagates
    -- teardown must actually complete on this host.

    F-D: the chmod must NOT follow a symlink. An arm can plant a symlink in the scratch
    tree; teardown only needs the link itself gone, never its target's mode changed. Use
    ``follow_symlinks=False`` where the platform supports it, else skip the chmod for a
    link (the retried ``func`` -- an unlink -- does not need the link writable).
    """
    if os.chmod in os.supports_follow_symlinks:
        os.chmod(path, stat.S_IWRITE, follow_symlinks=False)
    elif not os.path.islink(path):
        os.chmod(path, stat.S_IWRITE)
    func(path)


def _force_remove_onerror(func, path, _exc_info):  # type: ignore[no-untyped-def]
    """``shutil.rmtree(onerror=...)`` hook -- signature ``(func, path, exc_info)``.
    Removed in Python 3.14; used only on < 3.12 (see ``_rmtree`` below).
    """
    _chmod_and_retry(func, path)


def _force_remove_onexc(func, path, _exc):  # type: ignore[no-untyped-def]
    """``shutil.rmtree(onexc=...)`` hook -- signature ``(func, path, exception)``.
    Added in Python 3.12; the supported replacement for ``onerror``.
    """
    _chmod_and_retry(func, path)


def _rmtree(target) -> None:
    """``shutil.rmtree`` with the read-only-retry hook, on the API the running Python
    supports: ``onexc`` on >= 3.12 (``onerror`` is deprecated there and gone in 3.14),
    ``onerror`` on 3.11. ``ignore_errors=False`` either way -- behaviour is identical.
    """
    if sys.version_info >= (3, 12):
        shutil.rmtree(target, ignore_errors=False, onexc=_force_remove_onexc)
    else:
        shutil.rmtree(target, ignore_errors=False, onerror=_force_remove_onerror)
