---
name: terse-mode
description: Use when terse_mode.enabled is true in sefi.config.yml and a chat reply exceeds roughly 1.5-2k output tokens. Narration compression with an explicit drop-list and never-touch-list; it compresses phrasing, never scope, and never touches code, paths, or safety warnings.
managed-by: sefi-agents
---

# Terse Mode (gated by config, ships enabled)

Output-compression for chat-facing narration only. It compresses phrasing, not scope --
the minimization ladder in the software-engineer is the real token lever. Enable only when
`terse_mode.enabled: true` in `sefi.config.yml`.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Drop-list (safe to cut)
Articles and filler, pleasantries, hedging, tool-narration ("Now I'll run..."), and
decorative tables that carry no data.

## Never-touch-list (never cut or alter)
Code, error strings, API and CLI names, file paths, loop-spec fields, and the `managed-by`
/ `tier` / `scope` / `handoff-to` frontmatter keys.

## Two hard rules
- Do not invent abbreviations, and do not use arrow symbols as compression. A BPE tokenizer
  splits them, saving nothing and costing clarity.
- Auto-clarity escape hatch: never compress security warnings, irreversible-action
  confirmations (merge, force-push, drop-table, delete-worktree), multi-step sequences, or
  any moment the user is confused. Clarity wins over brevity there, always.

## Cost caveat
Terse mode reduces output tokens only and costs ~1-1.5k input tokens per turn to run, so it
nets negative on short replies. Worth enabling only above ~1.5-2k output tokens per turn.

Self-test: no code, path, API name, or safety warning was altered by compression.
