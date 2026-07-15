---
name: security-review
description: Use when reviewing a diff, dependency change, or configuration that touches a trust boundary before it can reach a PR. The security gate covering secrets, injection surfaces, unsafe constructs, dependency risk, authorization, and data handling.
managed-by: sefi-agents
---

# Security Review

Gate skill backing the security-engineer. This body is the Rule block; the expanded
checklist lives in `references/security-checklist.md`, read on demand. Review the diff,
not the intentions.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite file:line or mark UNKNOWN,
never guess.

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## Rule block (every reviewed diff is checked against all six)
1. Secrets: no credential, token, key, or connection string in code, fixtures, logs, or
   CI config -- placeholders only. Never open a secret-bearing file to verify it; name
   the missing variable instead.
2. Injection: every input reaching a shell, SQL/query builder, template engine, parser,
   or deserializer is validated or parameterized AT the trust boundary, not upstream of
   it.
3. Unsafe constructs: eval/exec on external input, unpinned curl-to-shell installs,
   YAML/pickle load on untrusted data, path traversal on user-supplied paths, disabled
   TLS verification.
4. Dependencies: a new dependency is a finding by default; it must name what it replaces
   and why an existing rung of the minimization ladder cannot do it.
5. Authorization: changed endpoints and handlers keep (or add) their permission checks;
   privilege boundaries are asserted in a test.
6. Data handling: PII is not newly logged, persisted, or sent to third parties; vault
   writes pass the memory-protocol privacy filter.

## Severity (aligned with the qa-engineer's scale)
Critical: exploitable as shipped -- halts the slice, inbox/ within 2 minutes (or before
this turn ends, whichever is sooner).
Important: weakens a boundary without an immediate exploit -- fix before PR.
Minor: hardening note -- recorded, does not block.

## Output shape
Numbered findings, each with file:line, severity, and a concrete failure scenario; or an
explicit "no findings at the reviewed surfaces" with the surfaces listed. A surface you
could not inspect is reported unreviewable, never assumed safe.

Never auto-merge or take a destructive action -- see
`sefi-orchestration/references/human-checkpoint.md` for the full rule and why.
See `references/security-checklist.md` for the expanded per-surface checklist.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "It's internal, no attacker reaches it." | Internal is one misconfig from external; boundaries hold regardless. |
| "The framework sanitizes by default." | Name the exact mechanism and version or it is unverified (UNKNOWN). |
| "Adding this dep saves an hour." | An hour saved now buys a supply-chain surface forever; justify per rule 4. |

Self-test: every finding cites file:line and a failure scenario; every clean verdict
names the surfaces actually reviewed.
