#!/usr/bin/env python3
"""Dependency-free local implementation helpers for Codebase Cartographer v0.9.1."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA = "sefi-codebase-map/v2"
EDGES = {"contains", "imports", "calls", "reads", "writes", "emits", "subscribes", "depends_on", "routes_to"}
FRESHNESS = {"ready", "pending", "stale", "missing"}
CLASSIFICATIONS = {"unchanged", "content-only", "structural", "unknown"}
RELATIONS = {"same", "behind", "ahead", "diverged", "unknown"}
HEX = re.compile(r"^[a-f0-9]{64}$")
IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9-]{0,79}$")
TEXT_EXTENSIONS = {".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".go", ".rs", ".java", ".kt", ".swift", ".rb", ".php", ".cs", ".sh", ".md", ".yml", ".yaml", ".json", ".toml", ".html", ".css", ".scss", ".sql"}
SECRET = re.compile(r"(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:sk|pk|ghp|github_pat|xox[baprs])[-_A-Za-z0-9]{8,}\b|\b(?:password|secret|token|api[_-]?key)\s*[:=]\s*[\"']?[^\s\"']+|://[^/@\s]+:[^/@\s]+@)", re.I)


def die(message: str) -> None:
    raise ValueError(message)


def now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_hash(path: Path) -> str:
    return digest(path.read_bytes())


def atomically_write(path: Path, value: Any) -> None:
    if contains_secret(value):
        die("credential-shaped content remains in generated artifact")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as out:
            if isinstance(value, str):
                out.write(value)
            else:
                json.dump(value, out, indent=2, sort_keys=True)
                out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def contains_secret(value: Any) -> bool:
    if isinstance(value, str):
        return bool(SECRET.search(value))
    if isinstance(value, list):
        return any(contains_secret(item) for item in value)
    if isinstance(value, dict):
        return any(contains_secret(item) for item in value.values())
    return False


def root_path(raw: str) -> Path:
    root = Path(raw).resolve()
    if not root.is_dir():
        die("root is not a directory")
    return root


def safe_relative(root: Path, raw: str) -> Path:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        die("path must be a repository-relative POSIX path")
    value = (root / raw).resolve()
    try:
        value.relative_to(root)
    except ValueError:
        die("unsafe path outside repository root")
    if value.is_symlink():
        die("symlink paths are not allowed")
    return value


def command(root: Path, *args: str) -> str | None:
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def git_info(root: Path) -> dict[str, str]:
    head = command(root, "rev-parse", "HEAD") or "unknown"
    common = command(root, "rev-parse", "--git-common-dir")
    dirty = command(root, "status", "--porcelain=v1")
    common_value = str((root / common).resolve()) if common else "unknown"
    identity = digest((str(root.resolve()) + "\0" + common_value).encode())
    return {"commit": head, "dirty": "dirty" if dirty else "clean" if common else "unknown", "worktree_id": identity}


def relation(root: Path, prior: str, current: str) -> str:
    if prior == current:
        return "same"
    if prior == "unknown" or current == "unknown":
        return "unknown"
    if command(root, "cat-file", "-e", f"{prior}^{{commit}}") is None or command(root, "cat-file", "-e", f"{current}^{{commit}}") is None:
        return "unknown"
    if command(root, "merge-base", "--is-ancestor", prior, current) is not None:
        return "behind"
    if command(root, "merge-base", "--is-ancestor", current, prior) is not None:
        return "ahead"
    return "diverged"


def deletion_is_established(root: Path, path: str, node: dict[str, Any], previous: str, current: str) -> bool:
    """Accept an incremental symbol loss only when Git shows its removed declaration."""
    if previous != "unknown" and current != "unknown":
        diff = command(root, "diff", "--unified=0", previous, current, "--", path)
    else:
        diff = command(root, "diff", "--unified=0", "--", path)
    if not diff:
        return False
    name = re.escape(str(node.get("name", "")))
    kind = str(node.get("type", ""))
    patterns = {
        "function": rf"^-.*(?:def|function)\s+{name}\b",
        "class": rf"^-.*class\s+{name}\b",
        "type": rf"^-.*(?:interface|type)\s+{name}\b",
    }
    return bool(re.search(patterns.get(kind, rf"^-.*\b{name}\b"), diff, re.M))


def inventory(root: Path, target: Path) -> list[Path]:
    result: list[Path] = []
    for candidate in sorted(target.rglob("*")):
        if not candidate.is_file() or candidate.is_symlink():
            continue
        relative = candidate.relative_to(root).as_posix()
        if relative.startswith((".git/", ".sefi/", "state/")):
            continue
        result.append(candidate)
    return result


def text_content(path: Path) -> str | None:
    if path.suffix.lower() not in TEXT_EXTENSIONS or path.stat().st_size > 1_000_000:
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    return text.replace("\r\n", "\n").replace("\r", "\n")


def evidence_id(relative: str, line: int, text: str) -> str:
    return "e-" + digest(f"{relative}\0{line}\0{text}".encode())[:16]


def extract(root: Path, path: Path, baseline: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str | None]:
    relative = path.relative_to(root).as_posix()
    content = text_content(path)
    if content is None:
        return [], [], None
    nodes: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    kind_patterns = (
        ("function", re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)\s*\(")),
        ("function", re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(")),
        ("class", re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_$][\w$]*)\b")),
        ("type", re.compile(r"^\s*(?:export\s+)?(?:interface|type)\s+([A-Za-z_$][\w$]*)\b")),
    )
    facts: list[str] = [f"owner:{relative}", f"subsystem:{relative.split('/', 1)[0]}"]
    lines = content.split("\n")
    for line_no, line in enumerate(lines, 1):
        for kind, pattern in kind_patterns:
            match = pattern.search(line)
            if not match:
                continue
            name = match.group(1)
            source_hash = digest(line.encode())
            identifier = "n-" + digest(f"{relative}\0{kind}\0{name}".encode())[:16]
            evidence.append({"id": evidence_id(relative, line_no, line), "path": relative, "start_line": line_no, "end_line": line_no, "sha256": source_hash, "baseline": baseline, "origin": "git-rg", "derivation": "observed", "confidence": "high"})
            nodes.append({"id": identifier, "type": kind, "name": name, "subsystem": relative.split("/", 1)[0], "evidence_ids": [evidence[-1]["id"]], "confidence": "high", "freshness": "ready"})
            signature_lines = [line.split("#", 1)[0].strip()]
            if kind == "function" and ")" not in line:
                for continuation in lines[line_no:]:
                    signature_lines.append(continuation.split("#", 1)[0].strip())
                    if ")" in continuation:
                        break
            signature = re.sub(r"\s+", " ", " ".join(signature_lines))
            facts.append(f"node:{kind}:{name}:signature:{signature}:export:{'export' in signature}")
            break
        import_match = re.match(r"\s*(?:from\s+([\w./-]+)\s+import|import\s+([\w./-]+)|(?:import|export).*?from\s+['\"]([^'\"]+))", line)
        if import_match:
            facts.append("import:" + next(value for value in import_match.groups() if value is not None))
    return nodes, evidence, digest("\n".join(sorted(set(facts))).encode())


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file() or path.is_symlink():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def validate_map(root: Path, value: dict[str, Any]) -> None:
    if contains_secret(value):
        die("credential-shaped content is not allowed in map artifacts")
    if value.get("schema") != SCHEMA:
        die("unsupported map schema")
    if not IDENTIFIER.fullmatch(value.get("slug", "")):
        die("invalid map slug")
    if value.get("baseline_relationship") not in RELATIONS:
        die("invalid baseline relationship")
    if value.get("status") not in {"ready", "pending", "stale", "needs-attention"}:
        die("invalid map status")
    if not HEX.fullmatch(value.get("inventory_hash", "")) or not HEX.fullmatch(value.get("worktree_id", "")):
        die("invalid map hashes")
    baseline = value.get("baseline")
    if not isinstance(baseline, dict) or not isinstance(baseline.get("commit"), str) or baseline.get("dirty_tree") not in {"clean", "dirty", "unknown"}:
        die("invalid baseline")
    target = safe_relative(root, value.get("target"))
    if not target.is_dir():
        die("map target is missing")
    if not isinstance(value.get("target_changed_paths"), list) or not all(isinstance(path, str) for path in value["target_changed_paths"]):
        die("invalid target-scoped changed paths")
    files = value.get("files")
    evidence = value.get("evidence")
    nodes = value.get("nodes")
    relationships = value.get("relationships")
    if not all(isinstance(item, list) for item in (files, evidence, nodes, relationships, value.get("subsystems"), value.get("unresolved_relationships"), value.get("dynamic_boundaries"), value.get("likely_affected_tests"))):
        die("map collections must be lists")
    evidence_ids: set[str] = set()
    for item in evidence:
        if not isinstance(item, dict) or item.get("id") in evidence_ids:
            die("invalid or duplicate evidence")
        evidence_ids.add(item["id"])
        path = safe_relative(root, item.get("path"))
        if not isinstance(item.get("start_line"), int) or not isinstance(item.get("end_line"), int):
            die("invalid evidence line range")
        if item["start_line"] < 1 or item["end_line"] < item["start_line"]:
            die("invalid evidence line range")
        if not HEX.fullmatch(item.get("sha256", "")) or item.get("origin") not in {"git-rg", "graft", "codegraph", "cartographer", "direct-repo", "user-supplied"} or item.get("derivation") not in {"observed", "imported", "heuristic"}:
            die("invalid evidence")
        if not path.is_file():
            die("missing evidence path")
        text = text_content(path)
        if text is None:
            die("evidence source is not readable text")
        lines = text.split("\n")
        if item["end_line"] > len(lines):
            die("evidence line range is outside source")
        current_hash = digest("\n".join(lines[item["start_line"] - 1:item["end_line"]]).encode())
        if current_hash != item["sha256"]:
            die("stale evidence cannot validate as current")
    paths: set[str] = set()
    for item in files:
        if not isinstance(item, dict) or item.get("path") in paths:
            die("invalid or duplicate file record")
        paths.add(item["path"])
        current_path = safe_relative(root, item["path"])
        if item.get("freshness") not in FRESHNESS or item.get("classification") not in CLASSIFICATIONS or not isinstance(item.get("freshness_reason"), str) or not isinstance(item.get("last_checked_baseline"), str):
            die("invalid file freshness or classification")
        for key in ("indexed_content_hash", "current_content_hash"):
            if item.get(key) != "missing" and not HEX.fullmatch(item.get(key, "")):
                die("invalid file content hash")
        if item.get("structural_hash") != "unknown" and not HEX.fullmatch(item.get("structural_hash", "")):
            die("invalid structural hash")
        if item["freshness"] == "ready":
            if not current_path.is_file() or file_hash(current_path) != item["current_content_hash"]:
                die("stale file evidence cannot validate as current")
    node_ids: set[str] = set()
    for node in nodes:
        if not isinstance(node, dict) or node.get("id") in node_ids:
            die("invalid or duplicate node")
        node_ids.add(node["id"])
        if not isinstance(node.get("type"), str) or not isinstance(node.get("name"), str) or not isinstance(node.get("subsystem"), str) or node.get("confidence") not in {"low", "medium", "high"} or node.get("freshness") not in FRESHNESS or not set(node.get("evidence_ids", [])).issubset(evidence_ids):
            die("node has invalid evidence or freshness")
    for edge in relationships:
        if not isinstance(edge, dict) or edge.get("type") not in EDGES or edge.get("freshness") not in FRESHNESS or edge.get("derivation") not in {"observed", "imported", "heuristic"}:
            die("invalid relationship type")
        if edge.get("source") not in node_ids or edge.get("target") not in node_ids or not set(edge.get("evidence_ids", [])).issubset(evidence_ids):
            die("relationship has dangling references")


def map_repository(root: Path, slug: str, target_raw: str) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(slug):
        die("slug must be lowercase kebab case")
    target = safe_relative(root, target_raw)
    if not target.is_dir():
        die("target must be a directory")
    destination = root / "state" / f"codebase-map-{slug}.json"
    previous = load_json(destination)
    info = git_info(root)
    if previous and previous.get("worktree_id") != info["worktree_id"]:
        # A copied state/ directory must never lend source evidence to a different
        # worktree. Build a new current-worktree map instead of silently reusing it.
        previous = None
    source = inventory(root, target)
    inventory_hash = digest("\n".join(f"{path.relative_to(root).as_posix()}:{file_hash(path)}" for path in source).encode())
    old_files = {item["path"]: item for item in previous.get("files", [])} if previous else {}
    prior_commit = previous.get("baseline", {}).get("commit", "unknown") if previous else info["commit"]
    map_relation = relation(root, prior_commit, info["commit"]) if previous else ("same" if info["commit"] != "unknown" else "unknown")
    if previous and map_relation in {"ahead", "diverged", "unknown"}:
        candidate = dict(previous)
        candidate["status"] = "needs-attention"
        candidate["baseline_relationship"] = map_relation
        local = root / ".sefi" / "cartographer" / slug
        atomically_write(local / "candidate-map.json", candidate)
        atomically_write(local / "incremental-diagnostics.json", {"schema": "sefi-cartographer-diagnostics/v1", "status": "needs-attention", "reason": "explicit base or full rebuild is required for this baseline relationship", "baseline_relationship": map_relation, "generated_at": now()})
        return candidate
    files: list[dict[str, Any]] = []
    nodes: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    for path in source:
        relative = path.relative_to(root).as_posix()
        content_hash = file_hash(path)
        extracted_nodes, extracted_evidence, structural = extract(root, path, info["commit"])
        old = old_files.get(relative)
        if not old:
            classification = "unchanged" if not previous else "structural"
            indexed = content_hash
        elif old.get("current_content_hash") == content_hash:
            classification, indexed = "unchanged", old.get("indexed_content_hash", content_hash)
        elif structural is not None and old.get("structural_hash") == structural:
            classification, indexed = "content-only", old.get("current_content_hash", "missing")
        else:
            classification, indexed = "structural" if structural is not None else "unknown", old.get("current_content_hash", "missing")
        files.append({"path": relative, "indexed_content_hash": indexed, "current_content_hash": content_hash, "structural_hash": structural or "unknown", "classification": classification, "freshness": "ready", "freshness_reason": "current inventory checked", "last_checked_baseline": info["commit"]})
        nodes.extend(extracted_nodes)
        evidence.extend(extracted_evidence)
    # Missing tracked files are explicit deletions only; never reuse their old evidence.
    present = {item["path"] for item in files}
    for relative in sorted(set(old_files) - present):
        files.append({"path": relative, "indexed_content_hash": old_files[relative].get("current_content_hash", "missing"), "current_content_hash": "missing", "structural_hash": "unknown", "classification": "structural", "freshness": "missing", "freshness_reason": "file is absent from current inventory", "last_checked_baseline": info["commit"]})
    target_relative = target.relative_to(root).as_posix()
    changed_output = command(root, "diff", "--name-only", prior_commit, info["commit"], "--", target_relative) if map_relation == "behind" else command(root, "diff", "--name-only", "--", target_relative)
    changed_paths = sorted(path for path in (changed_output or "").splitlines() if path)
    value = {"schema": SCHEMA, "slug": slug, "baseline": {"commit": info["commit"], "dirty_tree": info["dirty"]}, "baseline_relationship": map_relation, "target": target_relative, "target_changed_paths": changed_paths, "worktree_id": info["worktree_id"], "inventory_hash": inventory_hash, "status": "pending" if map_relation == "unknown" else "ready", "files": files, "nodes": nodes, "relationships": [], "evidence": evidence, "subsystems": sorted({node["subsystem"] for node in nodes}), "unresolved_relationships": [], "dynamic_boundaries": [], "likely_affected_tests": [], "delta": None, "connector_receipt": None, "context_packet_manifest": None, "generated_at": now()}
    if previous:
        old_evidence = {item["id"]: item for item in previous.get("evidence", [])}
        new_ids = {item["id"] for item in nodes}
        unexplained: list[dict[str, str]] = []
        for old_node in previous.get("nodes", []):
            if old_node.get("id") in new_ids:
                continue
            evidence_ids = old_node.get("evidence_ids", [])
            old_path = old_evidence.get(evidence_ids[0], {}).get("path") if evidence_ids else None
            if old_path and deletion_is_established(root, old_path, old_node, prior_commit, info["commit"]):
                continue
            unexplained.append({"node": str(old_node.get("id", "unknown")), "path": str(old_path or "unknown"), "reason": "symbol loss was not established by current Git evidence"})
        if unexplained:
            value["status"] = "needs-attention"
            local = root / ".sefi" / "cartographer" / slug
            atomically_write(local / "candidate-map.json", value)
            atomically_write(local / "incremental-diagnostics.json", {"schema": "sefi-cartographer-diagnostics/v1", "status": "needs-attention", "unexplained_symbol_loss": unexplained, "generated_at": now()})
            return value
    validate_map(root, value)
    atomically_write(destination, value)
    summary = f"# Codebase map: {slug}\n\nStatus: ready\n\nNodes: {len(nodes)}\n\nRelationships: 0\n\nEvidence is stored in `codebase-map-{slug}.json`.\n"
    atomically_write(root / "state" / f"codebase-map-{slug}.md", summary)
    cache = root / ".sefi" / "cartographer" / "cache" / slug / "map.json"
    atomically_write(cache, value)
    return value


def context(root: Path, slug: str, target: str, budget: int) -> None:
    if budget < 4000 or budget > 64000:
        die("budget must be between 4,000 and 64,000")
    mapping = load_json(root / "state" / f"codebase-map-{slug}.json")
    if not mapping:
        die("current validated map is required")
    validate_map(root, mapping)
    if mapping.get("status") != "ready":
        die("a ready map is required for a context packet")
    target_path = safe_relative(root, target)
    if not target_path.is_dir():
        die("context target is missing")
    target_relative = target_path.relative_to(root).as_posix()
    target_prefix = f"{target_relative.rstrip('/')}/"
    header = "# Cartographer context packet\n\n"
    entries: list[str] = []
    used = (len(header.encode("utf-8")) + 1) // 2
    omitted: list[str] = []
    for record in sorted(mapping["files"], key=lambda item: item["path"]):
        if target_relative != "." and record["path"] != target_relative and not record["path"].startswith(target_prefix):
            omitted.append(record["path"])
            continue
        if record["freshness"] != "ready":
            omitted.append(record["path"])
            continue
        path = safe_relative(root, record["path"])
        text = text_content(path)
        if text is None:
            omitted.append(record["path"])
            continue
        structural = "\n".join(line for line in text.splitlines() if re.search(r"\b(def|class|function|import|from|export|interface|type)\b", line))
        chunk = f"## {record['path']}\n\n```text\n{structural}\n```\n"
        estimate = (len(chunk.encode("utf-8")) + 1) // 2
        if used + estimate > budget:
            omitted.append(record["path"])
            continue
        entries.append(chunk)
        used += estimate
    location = root / ".sefi" / "cartographer" / slug
    packet = location / "packet-001.md"
    packet_text = header + "\n".join(entries)
    actual_estimate = (len(packet_text.encode("utf-8")) + 1) // 2
    if actual_estimate > budget:
        die("context packet exceeds its configured estimate")
    atomically_write(packet, packet_text)
    manifest = {"schema": "sefi-context-packets/v1", "source_map": f"state/codebase-map-{slug}.json", "source_map_hash": file_hash(root / "state" / f"codebase-map-{slug}.json"), "target": target_path.relative_to(root).as_posix(), "budget": budget, "estimation": "ceiling(UTF-8 byte count / 2)", "packets": [{"path": packet.relative_to(root).as_posix(), "sha256": file_hash(packet), "estimated_tokens": actual_estimate}], "detail_levels": {record["path"]: "structural" if record["path"] not in omitted else "directory-only" for record in mapping["files"]}, "omitted": omitted, "generated_at": now()}
    atomically_write(location / "manifest.json", manifest)


def visualize(root: Path, slug: str) -> None:
    mapping = load_json(root / "state" / f"codebase-map-{slug}.json")
    if not mapping:
        die("current validated map is required")
    validate_map(root, mapping)
    safe = html.escape(json.dumps(mapping, sort_keys=True))
    body = "<!doctype html><meta charset=utf-8><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\"><title>Cartographer viewer</title><style>body{font-family:system-ui;margin:2rem}pre{white-space:pre-wrap;word-break:break-word}button:focus,select:focus{outline:3px solid #06c}</style><h1>Codebase map</h1><label>Field <select id=field><option value=all>All evidence</option><option value=subsystem>Subsystem</option><option value=type>Node type</option><option value=confidence>Confidence</option><option value=freshness>Freshness</option><option value=origin>Origin</option><option value=derivation>Derivation</option></select></label><label>Value <select id=value><option value=all>All</option></select></label><button id=toggle>Toggle raw map</button><pre id=map hidden data-map=\"" + safe + "\"></pre><script>let m=document.getElementById('map'),d=JSON.parse(m.dataset.map),f=document.getElementById('field'),v=document.getElementById('value');function all(){return[].concat(d.nodes,d.evidence,d.files,d.relationships)}function values(){let k=f.value;v.innerHTML='<option value=all>All</option>';if(k!='all')[...new Set(all().map(x=>x[k]).filter(Boolean))].sort().forEach(x=>v.add(new Option(x,x)))}function show(){let k=f.value,q=v.value,x=JSON.parse(JSON.stringify(d));if(k!='all'&&q!='all'){x.nodes=x.nodes.filter(n=>n[k]===q);x.evidence=x.evidence.filter(e=>e[k]===q);x.files=x.files.filter(a=>a[k]===q);x.relationships=x.relationships.filter(r=>r[k]===q)}m.textContent=JSON.stringify(x,null,2)}values();show();f.onchange=()=>{values();show()};v.onchange=show;document.getElementById('toggle').onclick=()=>m.hidden=!m.hidden</script>"
    atomically_write(root / ".sefi" / "cartographer" / slug / "viewer.html", body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    map_cmd = sub.add_parser("map")
    map_cmd.add_argument("--root", required=True)
    map_cmd.add_argument("--slug", required=True)
    map_cmd.add_argument("--target", required=True)
    valid = sub.add_parser("validate")
    valid.add_argument("--root", required=True)
    valid.add_argument("--map", required=True)
    ctx = sub.add_parser("context")
    ctx.add_argument("--root", required=True)
    ctx.add_argument("--slug", required=True)
    ctx.add_argument("--target", required=True)
    ctx.add_argument("--budget", type=int, default=24000)
    view = sub.add_parser("visualize")
    view.add_argument("--root", required=True)
    view.add_argument("--slug", required=True)
    args = parser.parse_args()
    try:
        root = root_path(args.root)
        if args.command == "map":
            map_repository(root, args.slug, args.target)
        elif args.command == "validate":
            target = safe_relative(root, args.map)
            value = load_json(target)
            if not value:
                die("map is invalid JSON")
            validate_map(root, value)
        elif args.command == "context":
            context(root, args.slug, args.target, args.budget)
        else:
            visualize(root, args.slug)
        return 0
    except (ValueError, OSError) as error:
        print(f"cartographer-runtime: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
