#!/usr/bin/env python3
"""Offline validators and atomic persistence for Sefi documentation Claims.

Markdown remains the documentation source of truth. This helper keeps only the small,
verifiable sidecar records required to detect stale factual statements.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA = "sefi-doc-claims/v1"
MANIFEST_SCHEMA = "sefi-docs-manifest/v1"
ORIGINS = {"git-rg", "graft", "codegraph", "cartographer", "direct-repo", "user-supplied"}
DERIVATIONS = {"observed", "imported", "heuristic"}
CONFIDENCE = {"low", "medium", "high"}
DECISIONS = {"confirm", "update", "retract", "replace"}
HEX = re.compile(r"^[a-f0-9]{64}$")
CLAIM_ID = re.compile(r"^[a-z0-9][a-z0-9-]*-c[0-9]{4,}$")
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\b(?:sk|pk|ghp|github_pat|xox[baprs])[-_A-Za-z0-9]{8,}\b", re.I),
    re.compile(r"\b(?:password|secret|token|api[_-]?key)\s*[:=]\s*[^\s\"']+", re.I),
    re.compile(r"://[^/@\s]+:[^/@\s]+@", re.I),
)


def fail(message: str) -> None:
    raise ValueError(message)


def utc_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def root_path(raw: str) -> Path:
    root = Path(raw).resolve()
    if not root.is_dir():
        fail("root is not a directory")
    return root


def safe_relative(root: Path, raw: str) -> Path:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        fail("path must be a non-empty repository-relative POSIX path")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        fail("unsafe path outside repository root")
    if candidate.is_symlink():
        fail("symlink paths are not accepted")
    return candidate


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe file: {path.name}")
    return sha256_bytes(path.read_bytes())


def normalized_text_hash(path: Path, start_line: int, end_line: int) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe evidence: {path.name}")
    lines = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if start_line < 1 or end_line < start_line or end_line > len(lines):
        fail("evidence line range is outside the source file")
    return sha256_bytes("\n".join(lines[start_line - 1:end_line]).encode("utf-8"))


def contains_secret(value: Any) -> bool:
    if isinstance(value, str):
        return any(pattern.search(value) for pattern in SECRET_PATTERNS)
    if isinstance(value, list):
        return any(contains_secret(item) for item in value)
    if isinstance(value, dict):
        return any(contains_secret(item) for item in value.values())
    return False


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe JSON file: {path.name}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid JSON: {error.msg}")
    if not isinstance(value, dict):
        fail("JSON object required")
    return value


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
            json.dump(payload, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def string(value: Any, name: str, maximum: int = 500) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum or "\n" in value:
        fail(f"invalid {name}")
    return value


def hash_value(value: Any, name: str) -> str:
    if not isinstance(value, str) or not HEX.fullmatch(value):
        fail(f"invalid {name}")
    return value


def validate_evidence(root: Path, evidence: Any, *, require_current: bool = False) -> dict[str, Any]:
    if not isinstance(evidence, dict):
        fail("evidence must be an object")
    string(evidence.get("id"), "evidence ID", 180)
    path_raw = string(evidence.get("path"), "evidence path", 500)
    start = evidence.get("start_line")
    end = evidence.get("end_line")
    if not isinstance(start, int) or not isinstance(end, int):
        fail("evidence line range must be integers")
    expected = hash_value(evidence.get("sha256"), "evidence SHA-256")
    string(evidence.get("baseline"), "evidence baseline", 180)
    if evidence.get("origin") not in ORIGINS:
        fail("invalid evidence origin")
    if evidence.get("derivation") not in DERIVATIONS:
        fail("invalid evidence derivation")
    if evidence.get("confidence") not in CONFIDENCE:
        fail("invalid evidence confidence")
    path = safe_relative(root, path_raw)
    current = normalized_text_hash(path, start, end)
    if require_current and expected != current:
        fail("evidence is stale")
    copy = dict(evidence)
    copy["current_sha256"] = current
    return copy


def validate_claims(root: Path, claims: dict[str, Any], *, verify_evidence: bool = False) -> None:
    if contains_secret(claims):
        fail("credential-shaped content is not allowed in documentation artifacts")
    if claims.get("schema") != SCHEMA:
        fail("invalid Claims schema")
    document = string(claims.get("document"), "document path", 500)
    safe_relative(root, document)
    next_number = claims.get("next_claim_number")
    if not isinstance(next_number, int) or next_number < 1:
        fail("invalid next_claim_number")
    hash_value(claims.get("verified_document_hash"), "verified document SHA-256")
    string(claims.get("verified_baseline"), "verified baseline", 180)
    items = claims.get("claims")
    if not isinstance(items, list) or not items:
        fail("Claims must contain at least one active Claim")
    ids: set[str] = set()
    duplicate_facts: set[tuple[str, tuple[str, ...]]] = set()
    highest = 0
    for claim in items:
        if not isinstance(claim, dict):
            fail("Claim must be an object")
        claim_id = string(claim.get("id"), "Claim ID", 180)
        if not CLAIM_ID.fullmatch(claim_id) or claim_id in ids:
            fail("invalid or duplicate Claim ID")
        ids.add(claim_id)
        highest = max(highest, int(claim_id.rsplit("-c", 1)[1]))
        statement = string(claim.get("statement"), "Claim statement", 1000)
        evidence = claim.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            fail("Claim must have evidence")
        normalized = [validate_evidence(root, item, require_current=verify_evidence) for item in evidence]
        fact = (statement.casefold(), tuple(sorted(item["id"] for item in normalized)))
        if fact in duplicate_facts:
            fail("duplicate active Claim statement with identical evidence")
        duplicate_facts.add(fact)
        string(claim.get("last_verified_baseline"), "Claim baseline", 180)
        string(claim.get("verified_at"), "Claim verification time", 80)
        string(claim.get("task_id"), "producing task ID", 180)
    if next_number <= highest:
        fail("next_claim_number must be greater than every active Claim ID")


def classify_claims(root: Path, claims: dict[str, Any], document: Path, baseline: str) -> dict[str, Any]:
    expected_document_hash = claims["verified_document_hash"]
    document_hash = sha256_file(document)
    findings: list[dict[str, str]] = []
    for claim in claims["claims"]:
        state = "current"
        reason = "all evidence matches"
        for evidence in claim["evidence"]:
            try:
                path = safe_relative(root, evidence["path"])
                actual = normalized_text_hash(path, evidence["start_line"], evidence["end_line"])
            except ValueError:
                state, reason = "unresolved", "source evidence is missing or unsafe"
                break
            if actual != evidence["sha256"]:
                state, reason = "stale", "source evidence changed"
                break
        findings.append({"id": claim["id"], "status": state, "reason": reason})
    return {
        "schema": "sefi-docs-preflight/v1",
        "document": claims["document"],
        "baseline": baseline,
        "document_hash": document_hash,
        "document_drift": document_hash != expected_document_hash,
        "claims": findings,
    }


def evidence_from_decision(root: Path, raw: dict[str, Any], baseline: str) -> dict[str, Any]:
    required = {"id", "path", "start_line", "end_line", "origin", "derivation", "confidence"}
    if not required.issubset(raw):
        fail("decision evidence is incomplete")
    path = safe_relative(root, string(raw["path"], "decision evidence path", 500))
    start, end = raw["start_line"], raw["end_line"]
    if not isinstance(start, int) or not isinstance(end, int):
        fail("decision evidence line range must be integers")
    if raw["origin"] not in ORIGINS or raw["derivation"] not in DERIVATIONS or raw["confidence"] not in CONFIDENCE:
        fail("invalid decision evidence provenance")
    return {
        "id": string(raw["id"], "decision evidence ID", 180),
        "path": path.relative_to(root).as_posix(),
        "start_line": start,
        "end_line": end,
        "sha256": normalized_text_hash(path, start, end),
        "baseline": baseline,
        "origin": raw["origin"],
        "derivation": raw["derivation"],
        "confidence": raw["confidence"],
    }


def statement_in_document(statement: str, document: Path) -> bool:
    normalized_statement = " ".join(statement.casefold().split())
    normalized_document = " ".join(document.read_text(encoding="utf-8").casefold().split())
    return normalized_statement in normalized_document


def finalize(root: Path, claims_path: Path, document_path: Path, baseline: str, decisions_path: Path, task: str, manifest_path: Path) -> None:
    claims = read_json(claims_path)
    validate_claims(root, claims)
    if document_path.relative_to(root).as_posix() != claims["document"]:
        fail("document does not match its Claims sidecar")
    if not decisions_path.is_file() or decisions_path.is_symlink():
        fail("decisions file is missing")
    raw_decisions = json.loads(decisions_path.read_text(encoding="utf-8"))
    if not isinstance(raw_decisions, list):
        fail("decisions must be a JSON list")
    preflight = classify_claims(root, claims, document_path, baseline)
    required = {item["id"] for item in preflight["claims"] if item["status"] in {"stale", "unresolved"}}
    seen: set[str] = set()
    decisions: dict[str, dict[str, Any]] = {}
    known = {claim["id"] for claim in claims["claims"]}
    for decision in raw_decisions:
        if not isinstance(decision, dict):
            fail("decision must be an object")
        claim_id = decision.get("id")
        if claim_id not in known or claim_id in seen:
            fail("unknown or duplicate Claim decision")
        if decision.get("decision") not in DECISIONS:
            fail("invalid Claim decision")
        seen.add(claim_id)
        decisions[claim_id] = decision
    if required != seen:
        fail("every stale or unresolved Claim needs exactly one decision")
    revised: list[dict[str, Any]] = []
    for claim in claims["claims"]:
        decision = decisions.get(claim["id"])
        if not decision:
            revised.append(claim)
            continue
        kind = decision["decision"]
        if kind == "confirm":
            updated = dict(claim)
            updated["evidence"] = [evidence_from_decision(root, item, baseline) for item in claim["evidence"]]
        elif kind == "update":
            updated = dict(claim)
            updated["statement"] = string(decision.get("statement"), "updated Claim statement", 1000)
            raw_evidence = decision.get("evidence")
            if not isinstance(raw_evidence, list) or not raw_evidence:
                fail("updated Claim needs evidence")
            updated["evidence"] = [evidence_from_decision(root, item, baseline) for item in raw_evidence]
        elif kind == "retract":
            if statement_in_document(claim["statement"], document_path):
                fail("retracted Claim statement remains in the document")
            continue
        else:  # replace
            if statement_in_document(claim["statement"], document_path):
                fail("replaced Claim statement remains in the document")
            statement = string(decision.get("statement"), "replacement Claim statement", 1000)
            raw_evidence = decision.get("evidence")
            if not isinstance(raw_evidence, list) or not raw_evidence:
                fail("replacement Claim needs evidence")
            claim_id = f"{claims['document'].replace('/', '-').replace('.', '-')}-c{claims['next_claim_number']:04d}"
            claims["next_claim_number"] += 1
            updated = {"id": claim_id, "statement": statement, "evidence": [evidence_from_decision(root, item, baseline) for item in raw_evidence]}
        updated["last_verified_baseline"] = baseline
        updated["verified_at"] = utc_now()
        updated["task_id"] = string(task, "task ID", 180)
        revised.append(updated)
    if not revised:
        fail("a managed material document cannot have an empty active Claim set")
    claims["claims"] = revised
    claims["verified_document_hash"] = sha256_file(document_path)
    claims["verified_baseline"] = baseline
    for claim in revised:
        if not statement_in_document(claim["statement"], document_path):
            fail("Claim statement no longer appears in meaning within its document")
    validate_claims(root, claims, verify_evidence=True)
    manifest = read_json(manifest_path) if manifest_path.exists() else {"schema": MANIFEST_SCHEMA, "documents": []}
    if manifest.get("schema") != MANIFEST_SCHEMA or not isinstance(manifest.get("documents"), list):
        fail("invalid documentation manifest")
    claims_hash = sha256_bytes((json.dumps(claims, indent=2, sort_keys=True) + "\n").encode("utf-8"))
    entry = {
        "document": claims["document"],
        "document_sha256": claims["verified_document_hash"],
        "claims": claims_path.relative_to(root).as_posix(),
        "claims_sha256": claims_hash,
        "source_baseline": baseline,
        "task_id": task,
        "validation": "passed",
        "completed_at": utc_now(),
    }
    manifest["documents"] = [item for item in manifest["documents"] if item.get("document") != entry["document"]] + [entry]
    manifest["documents"].sort(key=lambda item: item["document"])
    if contains_secret(claims) or contains_secret(manifest):
        fail("credential-shaped content is not allowed in documentation artifacts")
    atomic_json(claims_path, claims)
    atomic_json(manifest_path, manifest)


def validate_manifest(root: Path, manifest: dict[str, Any]) -> None:
    if contains_secret(manifest):
        fail("credential-shaped content is not allowed in documentation artifacts")
    if manifest.get("schema") != MANIFEST_SCHEMA or not isinstance(manifest.get("documents"), list):
        fail("invalid documentation manifest")
    seen: set[str] = set()
    for entry in manifest["documents"]:
        if not isinstance(entry, dict):
            fail("manifest entry must be an object")
        document = string(entry.get("document"), "manifest document", 500)
        if document in seen:
            fail("duplicate manifest document")
        seen.add(document)
        document_path = safe_relative(root, document)
        if sha256_file(document_path) != hash_value(entry.get("document_sha256"), "manifest document SHA-256"):
            fail("manifest document hash mismatch")
        claims_path = safe_relative(root, string(entry.get("claims"), "manifest Claims path", 500))
        if sha256_file(claims_path) != hash_value(entry.get("claims_sha256"), "manifest Claims SHA-256"):
            fail("manifest Claims hash mismatch")
        claims = read_json(claims_path)
        validate_claims(root, claims, verify_evidence=True)
        if claims.get("document") != document:
            fail("manifest document does not match Claims sidecar")
        string(entry.get("source_baseline"), "manifest source baseline", 180)
        string(entry.get("task_id"), "manifest task ID", 180)
        if entry.get("validation") != "passed":
            fail("manifest validation result is not passed")
        string(entry.get("completed_at"), "manifest completion time", 80)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("validate-claims", "preflight", "finalize"):
        command = sub.add_parser(name)
        command.add_argument("--root", required=True)
        command.add_argument("--claims", required=True)
    validate = sub.add_parser("validate-manifest")
    validate.add_argument("--root", required=True)
    validate.add_argument("--manifest", required=True)
    preflight = sub.choices["preflight"]
    preflight.add_argument("--document", required=True)
    preflight.add_argument("--baseline", required=True)
    preflight.add_argument("--run-id", default="manual")
    final = sub.choices["finalize"]
    final.add_argument("--document", required=True)
    final.add_argument("--baseline", required=True)
    final.add_argument("--decisions", required=True)
    final.add_argument("--task", required=True)
    final.add_argument("--manifest", required=True)
    args = parser.parse_args()
    try:
        root = root_path(args.root)
        if args.command == "validate-manifest":
            validate_manifest(root, read_json(safe_relative(root, args.manifest)))
        else:
            claims_path = safe_relative(root, args.claims)
            claims = read_json(claims_path)
            validate_claims(root, claims)
            if args.command == "preflight":
                document = safe_relative(root, args.document)
                report = classify_claims(root, claims, document, args.baseline)
                if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.run_id):
                    fail("invalid documentation run ID")
                atomic_json(root / ".sefi" / "docs" / args.run_id / "preflight.json", report)
                print(json.dumps(report, indent=2, sort_keys=True))
            elif args.command == "finalize":
                finalize(root, claims_path, safe_relative(root, args.document), args.baseline, Path(args.decisions).resolve(), args.task, safe_relative(root, args.manifest))
        return 0
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"docs-grounding: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
