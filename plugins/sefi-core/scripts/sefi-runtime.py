#!/usr/bin/env python3
"""Local, content-free persistence helpers used by Sefi's harness-neutral commands."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

LIFECYCLE = {"queued", "running", "completed", "failed", "cancelled", "needs-attention"}
FAILURES = {"routing", "model", "tool", "validation", "permission", "timeout", "internal", "none"}
TIERS = {"low", "mid", "high"}
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
UNKNOWN = "UNKNOWN"


def die(message: str) -> None:
    raise ValueError(message)


def root_path(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_dir():
        die(f"root is not a directory: {path}")
    return path


def safe_id(value: str, label: str) -> str:
    if not SAFE_ID.fullmatch(value):
        die(f"invalid {label}")
    return value


def sha256(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        return "missing"
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_path_reference(root: Path, raw: str) -> dict[str, str]:
    path = Path(raw).resolve()
    try:
        reference = path.relative_to(root).as_posix()
    except ValueError:
        reference = f"external:{path.name or 'unnamed'}"
    return {"path": reference, "sha256": sha256(path)}


def flush_directory(directory: Path) -> None:
    if os.name == "nt":
        return
    try:
        descriptor = os.open(directory, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(descriptor)
    except OSError:
        pass
    finally:
        os.close(descriptor)


def atomic_json(destination: Path, payload: dict[str, Any]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
        flush_directory(destination.parent)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run_receipt(args: argparse.Namespace) -> None:
    root = root_path(args.root)
    session = safe_id(args.session, "session")
    task = safe_id(args.task, "task")
    agent = safe_id(args.agent, "agent")
    if args.tier not in TIERS:
        die("invalid tier")
    if args.state not in LIFECYCLE:
        die("invalid lifecycle state")
    if args.failure not in FAILURES:
        die("invalid failure class")
    if not args.route or "\n" in args.route or len(args.route) > 80:
        die("invalid route result")
    if args.retry < 0 or args.retry > 1000:
        die("invalid retry count")
    directory = root / ".sefi" / "runs" / session
    payload = {
        "agent": agent,
        "failure_class": args.failure,
        "input": safe_path_reference(root, args.input),
        "lifecycle": "v0.8",
        "output": safe_path_reference(root, args.output),
        "recorded_at": now(),
        "retry_count": args.retry,
        "route_check": args.route,
        "session_id": session,
        "state": args.state,
        "task_id": task,
        "tier": args.tier,
    }
    atomic_json(directory / f"receipt-{task}.json", payload)


def continuation(args: argparse.Namespace) -> None:
    root = root_path(args.root)
    session = safe_id(args.session, "session")
    if not args.goal.strip() and not args.plan_step.strip():
        die("continuation requires an explicit goal or plan step")
    if args.state not in {"queued", "running", "needs-attention"}:
        die("continuation state must be queued, running, or needs-attention")
    if not args.reason.strip() or len(args.reason) > 280 or "\n" in args.reason:
        die("invalid continuation reason")
    payload = {
        "goal": args.goal.strip()[:280],
        "plan_step": args.plan_step.strip()[:80],
        "reason": args.reason.strip(),
        "recorded_at": now(),
        "session_id": session,
        "state": args.state,
    }
    atomic_json(root / ".sefi" / "runs" / session / "continuation.json", payload)


def source_files(source: Path) -> dict[str, str]:
    records: dict[str, str] = {}
    for path in sorted(source.rglob("*")):
        if path.is_file() and not path.is_symlink():
            records[path.relative_to(source).as_posix()] = sha256(path)
    return records


def run_git(arguments: list[str], workdir: Path) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "-C", str(workdir), *arguments],
            capture_output=True,
            check=False,
            text=True,
            timeout=15,
        )
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def describe_source(source: Path) -> tuple[str, str]:
    """Derive (source_version, source_commit) for a source tree.

    Version identity rule: the version is the source commit's git tag via
    `git describe --tags --exact-match`, never a guessed release number.
    (--tags because a plain describe only matches annotated tags; a
    lightweight tag on the source commit is still its version.) An untagged
    source records `unreleased-plus-<commit>`. Outside a git checkout both
    values are UNKNOWN.
    """
    directory = source.resolve()
    commit = run_git(["rev-parse", "HEAD"], directory)
    if not commit:
        return (UNKNOWN, UNKNOWN)
    tag = run_git(["describe", "--tags", "--exact-match", commit], directory)
    if tag:
        return (tag, commit)
    return (f"unreleased-plus-{commit}", commit)


def manifest_create(args: argparse.Namespace) -> None:
    root = root_path(args.root)
    source = Path(args.source).resolve()
    destination = Path(args.destination).resolve()
    if not source.is_dir() or not destination.is_dir():
        die("source and destination must be directories")
    files = source_files(source)
    missing = [name for name in files if not (destination / name).is_file()]
    if missing:
        die(f"destination is missing managed file: {missing[0]}")
    version, commit = describe_source(source)
    payload = {
        "format": "sefi-package-manifest/v1",
        "generated_at": now(),
        "managed_files": files,
        "source_commit": commit,
        "source_name": source.name,
        "source_version": version,
    }
    atomic_json(destination / ".sefi-agents-manifest.json", payload)
    # Reject a caller that points the manifest outside its requested root only after the
    # destination is verified; a package may legitimately live elsewhere during install.
    _ = root


def read_manifest(destination: Path) -> dict[str, Any]:
    # The check operation below keeps its own inline copy of this validation on
    # purpose: check must stay byte-identical in behavior for CI, so the diff
    # operation loads through this separate reader instead of sharing one.
    manifest_path = destination / ".sefi-agents-manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        die("package manifest is missing")
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        die(f"package manifest is invalid JSON: {error.msg}")
    if payload.get("format") != "sefi-package-manifest/v1" or not isinstance(payload.get("managed_files"), dict):
        die("package manifest has an invalid format")
    return payload


def manifest_diff(args: argparse.Namespace) -> None:
    # Three-way verdict comparing an installed manifest against a repo source
    # tree. Exit 0 (current): installed hashes and version match the source.
    # Exit 2 (stale): the source moved on; the message names the new version
    # and commit. Exit 1 (drift): installed files were user-modified; the
    # message names them. Errors (missing/invalid manifest) print
    # `sefi-runtime: ...` to stderr with no verdict line, so consumers must
    # parse the `package-manifest-diff:` stdout line, never the exit code alone.
    root = root_path(args.root)
    source = Path(args.source).resolve()
    destination = Path(args.destination).resolve()
    if not source.is_dir() or not destination.is_dir():
        die("source and destination must be directories")
    payload = read_manifest(destination)
    managed = payload["managed_files"]
    for relative in managed:
        candidate = (destination / relative).resolve()
        try:
            candidate.relative_to(destination)
        except ValueError:
            die("package manifest contains an unsafe path")
    installed_version = payload.get("source_version", UNKNOWN)
    if not isinstance(installed_version, str) or not installed_version:
        installed_version = UNKNOWN
    installed_commit = payload.get("source_commit", UNKNOWN)
    if not isinstance(installed_commit, str) or not installed_commit:
        installed_commit = UNKNOWN
    drift = sorted(
        relative
        for relative, wanted in managed.items()
        if sha256((destination / relative).resolve()) != wanted
    )
    if drift:
        print("package-manifest-diff: drift in installed files: " + ", ".join(drift))
        raise SystemExit(1)
    version, commit = describe_source(source)
    if managed == source_files(source) and installed_version == version and installed_commit == commit:
        print(f"package-manifest-diff: current (version {version} commit {commit})")
        return
    print(
        "package-manifest-diff: stale "
        f"(installed version {installed_version} commit {installed_commit}; "
        f"source version {version} commit {commit})"
    )
    raise SystemExit(2)
    _ = root


def manifest_dispatch(args: argparse.Namespace) -> None:
    if args.operation == "create":
        manifest_create(args)
    elif args.operation == "diff":
        manifest_diff(args)
    else:
        manifest_check(args)


def manifest_check(args: argparse.Namespace) -> None:
    root = root_path(args.root)
    destination = Path(args.destination).resolve()
    manifest_path = destination / ".sefi-agents-manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        die("package manifest is missing")
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        die(f"package manifest is invalid JSON: {error.msg}")
    if payload.get("format") != "sefi-package-manifest/v1" or not isinstance(payload.get("managed_files"), dict):
        die("package manifest has an invalid format")
    drift: list[str] = []
    for relative, wanted in payload["managed_files"].items():
        candidate = (destination / relative).resolve()
        try:
            candidate.relative_to(destination)
        except ValueError:
            die("package manifest contains an unsafe path")
        if sha256(candidate) != wanted:
            drift.append(relative)
    if drift:
        print("package-manifest: drift in managed files: " + ", ".join(drift), file=sys.stderr)
        raise SystemExit(1)
    _ = root


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    subs = command.add_subparsers(dest="command", required=True)

    receipt = subs.add_parser("receipt")
    receipt.add_argument("--root", required=True)
    receipt.add_argument("--session", required=True)
    receipt.add_argument("--task", required=True)
    receipt.add_argument("--agent", required=True)
    receipt.add_argument("--tier", required=True)
    receipt.add_argument("--state", required=True)
    receipt.add_argument("--input", required=True)
    receipt.add_argument("--output", required=True)
    receipt.add_argument("--route", required=True)
    receipt.add_argument("--failure", default="none")
    receipt.add_argument("--retry", type=int, required=True)
    receipt.set_defaults(handler=run_receipt)

    cont = subs.add_parser("continuation")
    cont.add_argument("--root", required=True)
    cont.add_argument("--session", required=True)
    cont.add_argument("--goal", default="")
    cont.add_argument("--plan-step", default="")
    cont.add_argument("--reason", required=True)
    cont.add_argument("--state", required=True)
    cont.set_defaults(handler=continuation)

    manifest = subs.add_parser("manifest")
    manifest.add_argument("operation", choices=("create", "check", "diff"))
    manifest.add_argument("--root", required=True)
    manifest.add_argument("--source")
    manifest.add_argument("--destination", required=True)
    manifest.set_defaults(handler=manifest_dispatch)
    return command


def main() -> int:
    try:
        args = parser().parse_args()
        if args.command == "manifest" and args.operation in ("create", "diff") and not args.source:
            die(f"manifest {args.operation} requires --source")
        args.handler(args)
        return 0
    except ValueError as error:
        print(f"sefi-runtime: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
