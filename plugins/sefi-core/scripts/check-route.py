#!/usr/bin/env python3
# check-route.py -- post-dispatch route-evidence assertion: did the harness actually run
# the model + reasoning effort this repo's tier map asked for?
#
#   check-route.py <harness> <requested-tier> <session-record-or-thread-id>
#
# Invoked through check-route.sh (a thin interpreter-resolving shim that keeps the exact
# `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh` path every agent/skill reference uses).
# Runs directly too, for tests: `python3 check-route.py ...`.
#
# WHY PYTHON, JUST HERE. The jq-free POSIX-sh parser this replaces was reduced across four
# review rounds for five fail-open shapes: a decoy rollout record (a nested "model" string,
# a nested turn_context object on a non-turn_context line, ...) could make a downgraded run
# report `match`. Those shapes are structurally impossible with a real JSON parser plus
# top-level-only dict access: a nested "model" is a string value the parser never treats as
# a key, a nested object is a dict the parser never descends into. `json.loads` per line +
# `record.get("type")` / `record.get("payload")` one level deep is the whole defense.
#
# The live `match` / `mismatch` / `invalid` path is CODEX-ONLY. claude-code exposes no
# per-agent route readback; opencode / hermes resolve every tier to the `flexible` sentinel
# so there is no requested model id to compare. Those cells stay honest -- no fake path is
# invented for a harness with no rollout.
#
# NEVER read, echo, or log rollout free text. Only `model`, `effort`, and the thread id
# leave this parser. No network calls. No write side effects. Nothing is shelled out,
# `eval`-ed, or followed for a write.
#
# The POSITIONAL 3rd argument is only ever matched against a strict lowercase-UUID regex
# or the `-` placeholder -- it is NEVER auto-detected as a file path. The hidden
# `--rollout-file PATH` / `--sessions-dir PATH` options are reachable ONLY by invoking
# check-route.py DIRECTLY (`python check-route.py ...`), which is trusted contributor-test
# tooling. Through the shim `check-route.sh` -- the one path every
# `${CLAUDE_PLUGIN_ROOT}/scripts/check-route.sh` reference resolves to -- EVERY positional
# argument (1, 2, and 3+) is forced after an argparse `--` marker, so an env-derived value
# expanded unquoted into ANY slot -- `$CODEX_THREAD_ID` in slot 3, or a stray leading-dash
# word word-splitting into slot 1-2 -- cannot smuggle `--rollout-file` and cannot redirect
# the check at an arbitrary JSONL (it becomes an arity / unknown-harness error: exit 2,
# no JSON).
#
# Exit codes:
#   0  match | not-applicable
#   1  mismatch | invalid | unavailable
#   2  usage error (bad arg count/option, non-printable char in an argument, unknown
#      harness, a model-map value that is not a bare identifier or an off-allowlist effort)
#      -- printed to stderr ONLY, never a JSON status line
#   3  no usable interpreter (emitted by the shim; also here if run under < 3.11 directly)

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MODEL_FOR = SCRIPT_DIR / "model-for.sh"

HARNESSES = ("claude-code", "codex", "opencode", "hermes")
EFFORTS = frozenset(
    ("minimal", "low", "medium", "high", "xhigh", "none", "ultra")
)
# Same bare-identifier shape the reduced check-route.sh gated on: a leading alnum, then up
# to 255 more of [A-Za-z0-9._:/-]. A model id off this shape never reaches JSON output.
MODEL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}\Z")
# Lowercase UUID only -- matches the Codex rollout filename convention (astral
# check-primary.py:28-30, inspect-agent-runtime.sh:100).
UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z"
)

# status -> process exit code.
_EXIT = {
    "match": 0,
    "not-applicable": 0,
    "mismatch": 1,
    "invalid": 1,
    "unavailable": 1,
}


def usage(message):
    """A usage error: stderr only, exit 2, NEVER a JSON status line."""
    print(f"ERROR: {message}", file=sys.stderr)
    print(
        "usage: check-route.py <harness> <requested-tier> "
        "<session-record-or-thread-id>",
        file=sys.stderr,
    )
    raise SystemExit(2)


def emit(
    status,
    reason,
    expected_model,
    expected_effort,
    observed_model="",
    observed_effort="",
):
    """One compact JSON line, fixed key order, no sort_keys. Every value here is a fixed
    literal, a model id already regex-gated to a bare identifier, or an effort word from
    EFFORTS -- none can carry a quote, a backslash, or free text into the JSON."""
    obj = {
        "status": status,
        "reason": reason,
        "expected_model": expected_model,
        "expected_effort": expected_effort,
        "observed_model": observed_model,
        "observed_effort": observed_effort,
    }
    print(json.dumps(obj, separators=(",", ":")))
    return _EXIT[status]


def has_nonprintable(value):
    # Mirrors the reduced check-route.sh guard `case $arg in *[![:print:]]*)`: reject any
    # control character (tab, newline, BEL, ESC, DEL, ...). Ordinary path characters,
    # including spaces, stay allowed.
    return not all(ch == " " or ch.isprintable() for ch in value)


def resolve_bash():
    """Absolute path to a real bash, found by walking PATH ourselves.

    A bare ["bash", ...] handed to subprocess on Windows is resolved by CreateProcess,
    which searches System32 before PATH and there finds the WSL relay stub (execvpe
    /bin/bash -> fails). Walking os.environ["PATH"] in order returns the Git-for-Windows
    bash that actually runs, and on POSIX just returns /bin/bash or /usr/bin/bash. The
    resulting path is absolute -- subprocess never does its own name lookup.

    There is deliberately NO environment override for the bash binary: the only source
    of a bash path is this validated PATH walk (isfile + X_OK). An attacker-set variable
    must not be able to point the model-for.sh subprocess at an arbitrary binary.
    """
    names = ("bash", "bash.exe") if os.name == "nt" else ("bash",)
    for directory in os.environ.get("PATH", os.defpath).split(os.pathsep):
        if not directory:
            continue
        for name in names:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
    return "bash"


def resolve_model_for(reasoning, harness, tier):
    """Resolve through the ONE resolver, every value behind a `--` end-of-options guard,
    passed as an argv list (no shell string). A non-zero exit is a usage error."""
    cmd = [resolve_bash(), str(MODEL_FOR)]
    if reasoning:
        cmd.append("--reasoning")
    cmd += ["--", harness, tier]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except OSError as exc:
        usage(f"cannot execute model-for.sh: {exc}")
    if proc.returncode != 0:
        field = "reasoning effort" if reasoning else "model"
        # Do not echo the raw requested-tier value (not allowlist-checked). `harness` is
        # safe -- it is one of the 4 allowlisted literals by the time we get here.
        usage(
            f"cannot resolve a {field} for the requested tier (harness='{harness}': "
            "unknown harness, unmapped tier, or unreadable model map)"
        )
    return proc.stdout.strip()


def resolve_sessions_dir(configured):
    if configured:
        return Path(configured).expanduser()
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home).expanduser() / "sessions"
    return Path.home() / ".codex" / "sessions"


def read_rollout(path, expected_model, expected_effort):
    """Read ONE rollout file. Only `model` / `effort` from the LAST top-level turn_context
    payload ever leave this function. Rollout free text is never touched.

    Streamed: one line at a time, keeping only the most recent top-level turn_context
    payload -- never a full records[] list, so a huge rollout (many lines) cannot OOM the
    parser. Per-LINE size is bounded only by available memory, though: a multi-MB single
    line is read whole. That is an accepted local-file allocation DoS, not a route-evidence
    failure -- a MemoryError on such a line maps to `invalid` / `rollout-unreadable` below
    (exit non-zero), so it never yields a wrong verdict.
    The except is deliberately wide: json.JSONDecodeError and UnicodeError are ValueError
    subclasses (covered by ValueError); a >4300-digit JSON int raises a bare ValueError;
    deep nesting raises RecursionError; an oversized allocation raises MemoryError. All of
    them are an unreadable rollout, not an uncaught traceback that would leak the
    interpreter's absolute path.
    """
    last_turn = None
    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
                record = json.loads(line)
                # Top level ONLY. A nested object carrying type=="turn_context" is a dict
                # this never descends into -- the decoy the shell version fell for.
                if (
                    isinstance(record, dict)
                    and record.get("type") == "turn_context"
                    and isinstance(record.get("payload"), dict)
                ):
                    # Forked rollout snapshots legitimately carry several turn_context
                    # records; the LAST is the effective route
                    # (inspect-agent-runtime.sh:190-193). A malformed last record fails
                    # noisily below -- it never falls back to an earlier good one.
                    last_turn = record["payload"]
    except (OSError, ValueError, RecursionError, MemoryError):
        return emit(
            "invalid", "rollout-unreadable", expected_model, expected_effort
        )

    if last_turn is None:
        return emit(
            "invalid", "turn-context-missing", expected_model, expected_effort
        )

    observed_model = last_turn.get("model")
    observed_effort = last_turn.get("effort")
    if (
        not isinstance(observed_model, str)
        or not observed_model
        or not MODEL_RE.match(observed_model)
        or not isinstance(observed_effort, str)
        or observed_effort not in EFFORTS
    ):
        return emit(
            "invalid", "turn-context-malformed", expected_model, expected_effort
        )

    if observed_model == expected_model and observed_effort == expected_effort:
        return emit(
            "match",
            "route-match",
            expected_model,
            expected_effort,
            observed_model,
            observed_effort,
        )
    return emit(
        "mismatch",
        "route-mismatch",
        expected_model,
        expected_effort,
        observed_model,
        observed_effort,
    )


def check_codex(record, sessions_dir_arg, expected_model, expected_effort):
    # The POSITIONAL 3rd arg is ONLY a thread id (or the `-` placeholder). It is never
    # auto-detected as a file path: a `$CODEX_THREAD_ID` (or a stray `./-`) pointing at
    # an arbitrary JSONL must not become authoritative route evidence and bypass
    # ${CODEX_HOME}/sessions. The hidden `--rollout-file PATH` / `--sessions-dir PATH`
    # options are reachable only by a DIRECT `python check-route.py` call (contributor
    # tests); through the shim, EVERY positional (1, 2, and 3+) arrives after an argparse
    # `--` marker, so an unquoted `$CODEX_THREAD_ID` that word-splits into
    # `- --rollout-file X` is an arity error (exit 2), never an honoured option.
    stripped = record.strip()
    # (a) literal `-` or empty-after-strip -> no thread id to resolve.
    if stripped in ("", "-"):
        return emit(
            "unavailable",
            "thread-id-unavailable",
            expected_model,
            expected_effort,
        )

    # (b) a lowercase UUID -> resolve the sessions dir and match rollout FILENAMES.
    if UUID_RE.match(record):
        sessions_dir = resolve_sessions_dir(sessions_dir_arg)
        try:
            if not sessions_dir.is_dir():
                return emit(
                    "unavailable",
                    "sessions-dir-unavailable",
                    expected_model,
                    expected_effort,
                )
            matches = sorted(
                path
                for path in sessions_dir.rglob(f"rollout-*-{record}.jsonl")
                if path.is_file()
            )
        except OSError:
            return emit(
                "unavailable",
                "sessions-dir-unavailable",
                expected_model,
                expected_effort,
            )
        if not matches:
            return emit(
                "unavailable",
                "rollout-unavailable",
                expected_model,
                expected_effort,
            )
        if len(matches) > 1:
            return emit(
                "invalid",
                "rollout-ambiguous",
                expected_model,
                expected_effort,
            )
        return read_rollout(matches[0], expected_model, expected_effort)

    # (c) anything else -> not a thread id we can resolve.
    return emit(
        "invalid", "thread-id-invalid", expected_model, expected_effort
    )


def build_parser():
    parser = argparse.ArgumentParser(
        prog="check-route.py",
        description=(
            "Post-dispatch route-evidence assertion: did the harness run the model + "
            "reasoning effort the tier map asked for? Live match/mismatch/invalid is "
            "Codex-only; other harnesses report unavailable / not-applicable."
        ),
    )
    parser.add_argument("harness", help="one of: " + " ".join(HARNESSES))
    parser.add_argument("tier", help="harness-neutral requested tier (e.g. high/mid/low)")
    parser.add_argument(
        "record",
        help=(
            "a lowercase-UUID thread id, or '-' when none is available (Codex only; "
            "ignored for other harnesses). NOT a file path -- use --rollout-file."
        ),
    )
    # Hidden, test-only: widens the READ scope for the Codex sessions directory search.
    parser.add_argument("--sessions-dir", default=None, help=argparse.SUPPRESS)
    # Hidden, test-only: read this rollout file directly, bypassing the thread-id /
    # sessions-dir resolution. Reachable ONLY by a DIRECT `python check-route.py` call
    # (trusted contributor tooling): the POSITIONAL 3rd arg is never file-auto-detected,
    # and through the shim `check-route.sh` EVERY positional (1, 2, and 3+) arrives after
    # an argparse `--` marker, so an env-derived value in ANY slot -- quoted or unquoted --
    # cannot reach this option and cannot point the check at an arbitrary JSONL.
    parser.add_argument("--rollout-file", default=None, help=argparse.SUPPRESS)
    return parser


def main(argv):
    if sys.version_info < (3, 11):
        print(
            "check-route: Python 3.11+ required; route check skipped", file=sys.stderr
        )
        return 3

    args = build_parser().parse_args(argv)

    for label, value in (
        ("harness", args.harness),
        ("requested-tier", args.tier),
        ("session-record", args.record),
        ("--sessions-dir", args.sessions_dir or ""),
        ("--rollout-file", args.rollout_file or ""),
    ):
        if has_nonprintable(value):
            usage(f"the {label} argument contains a non-printable character")

    if args.harness not in HARNESSES:
        usage(
            f"unsupported harness: {args.harness} "
            f"(expected one of: {' '.join(HARNESSES)})"
        )

    expected_model = resolve_model_for(False, args.harness, args.tier)
    expected_effort = resolve_model_for(True, args.harness, args.tier)

    # The tier map's output is a trust boundary: a malformed config/model-map.yml value
    # must never flow unchecked into emit(). Constrain it to the shape emit() promises.
    # The offending value and the raw requested-tier are NOT echoed to stderr -- only the
    # argument's role and the fixed failure. `harness` is safe to name (allowlist-checked
    # to 4 literals just above).
    if expected_model != "flexible" and not MODEL_RE.match(expected_model):
        usage(
            "the model resolved for the requested tier failed the bare-identifier "
            f"allowlist check (harness='{args.harness}')"
        )
    if expected_effort not in EFFORTS:
        usage(
            "the reasoning effort resolved for the requested tier failed the effort "
            f"allowlist check (harness='{args.harness}')"
        )

    # The flexible sentinel: no requested model id exists, so a comparison is undefined.
    if expected_model == "flexible":
        return emit(
            "not-applicable",
            "tier-resolves-to-flexible",
            expected_model,
            expected_effort,
        )

    if args.harness == "claude-code":
        return emit(
            "unavailable",
            "harness-exposes-no-route-readback",
            expected_model,
            expected_effort,
        )
    if args.harness == "hermes":
        return emit(
            "unavailable",
            "harness-model-readback-undocumented",
            expected_model,
            expected_effort,
        )
    if args.harness == "opencode":
        return emit(
            "unavailable",
            "session-record-format-undocumented",
            expected_model,
            expected_effort,
        )

    # Codex. The hidden --rollout-file option reads a rollout directly (test fixtures);
    # otherwise the positional 3rd arg is interpreted strictly as a thread id / `-`.
    if args.rollout_file is not None:
        return read_rollout(
            Path(args.rollout_file).expanduser(), expected_model, expected_effort
        )

    return check_codex(
        args.record, args.sessions_dir, expected_model, expected_effort
    )


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
