---
tags: [decision, policy, python, contributor-tooling]
type: policy
status: active
date-discovered: 2026-09-03
authorizing-person: human
evidence: astral-adoption Phase 3 check-route.py, Phase 4 benchmarks/
scope: all
---

# Python in Plugin Scripts: Contributor-Tooling Exception

## The Policy

Standard rule: No Python in plugin scripts (POSIX shell + Unix tools only).

Exception: Contributor-tooling scripts (dev-only, never in a dispatch path or CI loop) may use stdlib-only Python on the precedent that the repo already ships such tooling.

**Exception grant conditions:**
1. Script is contributor-tooling only (never invoked by an agent or in a dispatch loop).
2. Uses stdlib-only (no pip/venv dependencies).
3. Explicitly authorized by a human at each request (not a blanket exemption).
4. Documented in the script's header and in CHANGELOG.

## Evidence From Astral-Adoption Run

**Two scripts authorized under this exception:**

1. **Phase 3**: `plugins/sefi-core/scripts/check-route.py` (Python 3.11+, stdlib only).
   - Reason: The prior POSIX-shell route parser had 5 distinct fail-open shapes that a shell script cannot structurally prevent (no `json.loads` in shell). A real JSON parser was required.
   - Status: Shipped as a thin interpreter shim over a new stdlib-Python parser (exceptional authorization, one-time).

2. **Phase 4**: `benchmarks/scorecard.py` and `benchmarks/runner/` (Python 3.11+, stdlib only).
   - Reason: Paired-bootstrap JSONL statistics in shell is brittle and unreviewable at the needed size. Benchmark tooling is contributor-only (never in a dispatch loop).
   - Status: Shipped as dev-only benchmark scorer; no real benchmark run was made, so no token spend gate applies.

## Why This Exception Exists

- Benchmark and route-verification tooling are specialist domains where POSIX shell would be unmaintainable.
- These tools do not run in dispatch loops or agent flows (checked at gate time).
- The precedent of existing stdlib-Python contributor tooling in the repo makes the exception consistent.

## Renewal Terms

Each future request for Python in a plugin script must:
1. Be explicitly marked `requires: human-authorization`.
2. Include the same justification (stdlib-only, contributor-tooling, complexity reason).
3. Be approved by the same human authorization gate.

This is NOT a blanket exemption. Future requests will be reviewed and may be denied.

Related: [[memory/daily/2026-09-03]] (close-out note)
