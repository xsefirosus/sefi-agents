---
name: technical-writing
description: Use when writing or revising user-facing prose -- READMEs, changelogs, guides, adapter docs, or release notes. Audience-first structure with a quickstart before theory, every claim verified against the repo, and no invented benchmarks or features.
managed-by: sefi-agents
---

# Technical Writing

Craft skill backing the technical-writer. The audience is outside the team; the law is
that docs describe the tree as it is, verified.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: every command, path, flag, and
number is verified against the repo or an executed output -- or marked UNKNOWN, never
guessed.

## Rule block
1. Audience first: the first lines name who this is for and what they will accomplish.
   One doc, one audience -- an agent-targeted doc (Install.md) and a human-targeted doc
   (README) do not merge.
2. Quickstart before theory: the shortest working path (copy-pasteable) appears before
   any architecture explanation. A reader who leaves after 30 seconds should leave with
   working commands.
3. Verify-before-cite: run or open everything you document. A drifted command in a
   README is a bug with the same severity as a broken test.
4. Honest claims only: no invented benchmarks, no superlatives without a measurement, no
   documenting features that are not in the tree. Future work is labeled as such in a
   roadmap section or omitted.
5. Numbers carry sources: a figure is followed by where it comes from (a named report, a
   command output). Unlabeled estimates are cut.
6. One idea per sentence; concrete over abstract; second person for instructions ("run
   X"), not passive voice ("X should be run").
7. House constraints: plain ASCII (the unicode gate scans docs -- no emoji, no em-dash,
   no smart quotes), Keep-a-Changelog format for releases, fenced blocks for anything
   copy-pasteable.
8. Structure is scannable: a reader finds any fact via headings alone; no fact lives
   only in a paragraph's middle.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "A bigger number sells better." | An invented number sells once and costs credibility forever; cite or cut. |
| "Everyone claims 'blazingly fast'." | That is why it reads as slop; measure or say nothing. |
| "Document it now, ship it next week." | Docs describe the tree as it is; label future work or omit it. |

Self-test: every command in the doc was executed (or its file opened) during writing, and
every number names its source.
