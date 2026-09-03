"""Integrity gate for out-of-process benchmark trials.

``verify()`` is the security-critical core of the runner: it decides whether a trial
earned ``integrity_ok: true`` in its record. ``record.py`` sets that key LAST and ONLY
as ``integrity.verify(...) is True``; every other outcome omits the key and
``scorecard.py`` (scorecard.py:462-471) then excludes the trial.

INVARIANT -- every check below is MANDATORY and its ABSENCE is an explicit ``False``,
never a skip. This forecloses the meta-risk "an optional verification whose absence
fails open":

  * There is NO ``is not False`` anywhere -- the route check is ``captured is True``.
  * There is NO ``if <x> is not None:`` / ``if <x>_available:`` guard that lets a
    missing input SKIP a check.
  * There is NO early ``return True``.
  * There is NO inner ``try/except`` that swallows an error and continues as if the
    check had passed.
  * A missing / ``None`` / empty manifest fails at the explicit shape guard (check 0);
    a ``KeyError``, an ``AttributeError`` on ``route_result``, or an import failure ALL
    yield ``False`` via the single outer ``except Exception: return False``.

Standard library only (via ``benchmarks.runner.snapshot``).
"""

from __future__ import annotations

from benchmarks.runner import snapshot


def verify(pre_manifest, ref_manifest, post_manifest, allowed_paths, route_result) -> bool:
    """Return ``True`` ONLY if every mandatory integrity check passes.

    Checks, applied in order via ``ok = ok and <check>``:
      1. ``pre_manifest == ref_manifest`` -- the sandbox pre-run state is exactly the
         pinned-ref manifest (both produced by ``snapshot.snapshot()``).
      2. ``snapshot.diff(pre_manifest, post_manifest, allowed_paths) == []`` -- no
         out-of-allowlist change between pre-run and post-run state.
      3. ``route_result.captured is True`` -- route evidence was captured
         out-of-process by ``route.capture_route``.

    The ENTIRE body is wrapped in ``try: ... except Exception: return False``: any
    raised exception -- a ``None`` manifest, a ``KeyError``, an ``AttributeError`` on
    ``route_result``, an import failure -- yields ``False``, never a traceback.
    """
    try:
        ok = True
        # 0. EXPLICIT SHAPE GUARD (fail-closed): a missing / empty manifest must FAIL
        # here, by THIS line, never by relying on a downstream call raising. ``pre`` and
        # ``post`` must be non-empty dicts; ``ref`` must be a dict (it may legitimately
        # equal ``pre``). ``verify(None, None, None, [], rr)`` is ``False`` by this guard
        # alone -- ``snapshot.diff`` below is never reached (short-circuit).
        ok = ok and isinstance(pre_manifest, dict) and pre_manifest and isinstance(ref_manifest, dict) and isinstance(post_manifest, dict) and post_manifest
        # 1. sandbox pre-run state equals the pinned-ref manifest (exact dict equality).
        ok = ok and (pre_manifest == ref_manifest)
        # 2. no change outside the case's allowed_paths between pre and post.
        ok = ok and (snapshot.diff(pre_manifest, post_manifest, allowed_paths) == [])
        # 3. route evidence was captured out-of-process.
        ok = ok and (route_result.captured is True)
        return ok is True
    except Exception:
        return False
