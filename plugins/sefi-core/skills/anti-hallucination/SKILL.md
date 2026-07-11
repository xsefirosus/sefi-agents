---
name: anti-hallucination
description: Use when producing any factual output -- paths, APIs, numbers, citations, config keys, or claims about code behavior. The canonical no-invention rule every agent points to; unknown lookups become UNKNOWN, unrun executions become PENDING, and every claim traces to a source.
managed-by: sefi-agents
---

# Anti-Hallucination -- the canonical no-invention rule

This is the one place the rule is stated in full. Every agent's Output contract and every
skill links here with one line and never restates it (same pattern as the never-auto-merge
rule in `sefi-orchestration/references/human-checkpoint.md`).

User instructions always override this skill.

## The rule
1. Never invent a path, API name, function signature, config key, version number, metric,
   or citation. If a lookup is unknown, output the literal string UNKNOWN. If a value
   needs an execution you cannot perform (a checksum, a test result, a live metric),
   output PENDING; the caller computes it.
2. Every factual claim traces to one of: a file (cite file and line), an executed
   command's output (cite the command), or a named source (cite it). A claim with none of
   the three is not made.
3. Verify-before-cite: open the file or run the command BEFORE writing the claim, not
   after. Writing from memory of a file is how plausible-but-wrong paths ship.
4. Quote specs and contracts; do not paraphrase them from memory. A paraphrase drifts;
   a quote is checkable.
5. Numbers come only from executed commands or named first-party reports. A rounded
   estimate is labeled as one ("~", "estimated"), never presented as measured.
6. "I don't know" is a correct output. A plausible guess presented as fact is a defect
   with a severity, not a style issue.
7. Memory tie-in: only cross-task-validated claims earn `tier: fact` in the vault
   (memory-protocol promotion rules). A single observation stays `tier: trace`.

## Why this is structural here, not advice
The repo's mechanics assume it: the qa-engineer's evidence-pair rule re-verifies claims
by execution; state claims that disagree with git lose to git; telemetry states what
happened, never what was hoped. This skill is the writing-side counterpart of those
checking-side rules -- if agents never invent, the gates spend their budget on real
defects instead of fabricated context.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "The path is obviously src/utils.js." | Obvious is not verified; open it or write UNKNOWN. |
| "The user wants an answer, not UNKNOWN." | A wrong answer costs more than an honest gap; UNKNOWN is an answer. |
| "It's a standard API, I know its shape." | APIs drift by version; quote the installed one or mark UNKNOWN. |
| "A rough number makes the point better." | Label it an estimate or drop it; unlabeled estimates become 'facts' downstream. |
| "I verified it earlier in the session." | State moves; re-check before the claim ships in an output. |

Self-test: every factual claim in the output traces to a file, an executed command, or a
named source; every gap is marked UNKNOWN or PENDING, not filled in.
