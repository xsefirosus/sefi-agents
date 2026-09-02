"""Trial-record writer for out-of-process benchmark trials.

``build_record()`` assembles the trial dict that ``benchmarks/scorecard.py`` loads. It
uses RUNNER-OBSERVED values ONLY:

  * ``strategy`` / ``harness`` / ``trial`` / ``case_id`` / ``acceptance_checks`` -- the
    trial matrix the runner is executing;
  * ``wall_time_seconds`` / ``model_calls`` -- observed by the runner around the arm;
  * ``accepted`` / ``first_pass_accepted`` / ``rework_required`` -- from the
    ``acceptance`` dict the caller (``run.py``, step 7) computes by re-running the case
    ``acceptance_check`` from a PRISTINE copy OUTSIDE the sandbox
    (``run-sefi-benchmark/SKILL.md:75-85``);
  * ``case_fingerprint`` -- from ``benchmarks/cases.json`` (the caller passes it),
    NEVER from the arm;
  * ``route_evidence`` -- built from the ``RouteResult`` that ``route.capture_route``
    collected out-of-process by shelling out to ``check-route.sh``;
  * ``integrity_ok`` -- set LAST, and ONLY as an explicit ``True``.

This module imports NOTHING from ``arms.py`` and has NO code path that opens or reads
arm stdout / ``raw_log_path``. It imports ``RouteResult`` from ``route.py`` for typing
only.

Standard library only.
"""

from __future__ import annotations

from benchmarks.runner.route import RouteResult

_SCHEMA_VERSION = 1


def _text_or(value, fallback: str) -> str:
    """A stripped non-empty string from ``value``, else ``fallback``."""
    text = (value or "")
    if not isinstance(text, str):
        text = str(text)
    text = text.strip()
    return text or fallback


def _route_lane(route_result: RouteResult, *, role: str, task_id: str) -> dict:
    """One ``route_evidence`` lane built from a ``RouteResult``.

    ``check-route.sh`` emits ``observed_model=""`` / ``observed_effort=""`` for every
    non-``match`` status, and ``scorecard.py``'s ``_TEXT_FIELD_RE`` (scorecard.py:65,224)
    rejects the empty string. So an EMPTY observed value is mapped to the status word
    (e.g. ``"unavailable"`` / ``"not-applicable"``), which is charset-safe, and
    ``expected_model`` is OMITTED for that lane so ``scorecard.py`` reports
    ``model=unchecked`` (scorecard.py:56-58,436).

    A real ``match`` / ``mismatch`` lane keeps the actual observed/expected strings.
    """
    status = _text_or(route_result.status, "unavailable")
    observed_model = _text_or(route_result.observed_model, "")
    observed_effort = _text_or(route_result.observed_effort, "")
    expected_model = _text_or(route_result.expected_model, "")
    expected_effort = _text_or(route_result.expected_effort, "")

    lane = {"role": role, "task_id": task_id}
    if observed_model and observed_effort:
        # A gradeable lane: real observed model + effort came back.
        lane["model"] = observed_model
        lane["effort"] = observed_effort
        lane["expected_effort"] = expected_effort or status
        if expected_model:
            lane["expected_model"] = expected_model
    else:
        # Empty observed -> status word (charset-safe); expected_model OMITTED so the
        # route axis honestly shows model=unchecked.
        lane["model"] = status
        lane["effort"] = status
        lane["expected_effort"] = expected_effort or status
    return lane


def build_record(
    *,
    trial_id: str,
    case_id: str,
    trial: int,
    strategy: str,
    harness: str,
    acceptance_checks,
    acceptance: dict,
    wall_time_seconds: float,
    model_calls: int,
    case_fingerprint: str,
    route_result: RouteResult,
    integrity_ok_verified,
    route_role: str = "solo",
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    cost_usd: float | None = None,
) -> dict:
    """Assemble one trial record. See module docstring for the provenance rules.

    ``acceptance`` must be a dict carrying ``accepted`` / ``first_pass_accepted`` /
    ``rework_required`` (computed by the caller from a pristine out-of-sandbox re-run
    of the case ``acceptance_check``).

    ``integrity_ok_verified`` is the return value of ``integrity.verify(...)``. The
    ``integrity_ok`` key is written LAST and ONLY when that value ``is True``;
    otherwise the key is OMITTED entirely (never ``False``, never ``null``).
    """
    if not isinstance(acceptance, dict):
        raise TypeError("acceptance must be a dict of accepted/first_pass_accepted/rework_required")
    for key in ("accepted", "first_pass_accepted", "rework_required"):
        if key not in acceptance:
            raise ValueError(f"acceptance missing required key {key!r}")

    checks = list(acceptance_checks)
    if not checks or not all(isinstance(c, str) for c in checks):
        raise ValueError("acceptance_checks must be a non-empty list of strings")

    record: dict = {
        "schema_version": _SCHEMA_VERSION,
        "trial_id": trial_id,
        "case_id": case_id,
        "case_fingerprint": case_fingerprint,
        "trial": trial,
        "strategy": strategy,
        "harness": harness,
        "acceptance_checks": checks,
        "accepted": bool(acceptance["accepted"]),
        "first_pass_accepted": bool(acceptance["first_pass_accepted"]),
        "rework_required": bool(acceptance["rework_required"]),
        "wall_time_seconds": wall_time_seconds,
        "model_calls": model_calls,
        "route_evidence": [
            _route_lane(route_result, role=route_role, task_id=f"{trial_id}-{route_role}")
        ],
    }

    # Optional harness telemetry: included only when the caller has a real value.
    # Missing telemetry stays ABSENT (never 0) -- run-sefi-benchmark/SKILL.md.
    if input_tokens is not None:
        record["input_tokens"] = input_tokens
    if output_tokens is not None:
        record["output_tokens"] = output_tokens
    if cost_usd is not None:
        record["cost_usd"] = cost_usd

    # integrity_ok is set LAST and ONLY as an explicit True. Any other value -- False,
    # None, a forced-exception result, a truthy non-True -- OMITS the key, and
    # scorecard.py (scorecard.py:462-471) then excludes the trial from every delta and
    # from the route table.
    if integrity_ok_verified is True:
        record["integrity_ok"] = True
    return record
