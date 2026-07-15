---
name: memory-protocol
description: Use when reading from or writing to the memory vault, distilling notes, or maintaining the router. The Obsidian-style vault contract covering note frontmatter schemas, the router-based read ladder, the privacy-filtered append-only write path, and tier and scope promotion rules.
managed-by: sefi-agents
---

# Memory Protocol

The Obsidian-style vault is human-readable knowledge (`memory/`); machine bookkeeping is
`state/`. Never mix them. Obsidian recognizes only three built-in properties (`tags`,
`aliases`, `cssclasses`); every other key below is custom-but-queryable.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

## Note frontmatter

Decisions (`memory/decisions/<slug>.md`):
```yaml
---
tags: [decision, <project-slug>]
aliases: ["<short name>"]
status: proposed | accepted | superseded
superseded-by: ""          # path if superseded; append-only correction, never delete/rewrite the old note
supersedes: ""             # path this note supersedes (on the new note)
decided: YYYY-MM-DD        # Obsidian has NO built-in created/modified frontmatter -- use custom keys
updated: YYYY-MM-DD
tier: trace | policy | fact       # confidence/recurrence axis
scope: session | project | user   # who/how-long axis (session=daily/expiring, project=vault-local, user=durable operator facts)
keywords: comma, separated, terms
related: "[[other-note]]"         # QUOTED -- [[ is YAML-special; unquoted is invalid YAML
handoff-to: ""                    # agent slug if this write is also a handoff
managed-by: sefi-agents
---
```

Daily (`memory/daily/YYYY-MM-DD.md`), lighter:
```yaml
---
tags: [daily]
date: YYYY-MM-DD
tier: trace
scope: session
topic: <topic-slug>        # enables the Bases groupBy promotion view
managed-by: sefi-agents
---
```

Use a `> [!warning] Superseded` callout on superseded decisions, and `%%...%%` comments
for machine-only markers (invisible in reading view, greppable by the knowledge-manager).

## READ (router-based, never bulk-load)
1. Frontmatter-only scan first: `rg` the leading frontmatter across `memory/**`.
2. Open `memory/index.md`.
3. Follow at most 2 wikilinks. The budget counts `[[wikilinks]]` (in-vault) only;
   external references stay `[text](url)` Markdown links and never count against it.

Use `rg` for anything else. Never open a file > 100 KB without a stated need.

## WRITE (privacy-filtered, append-only)
1. Run the privacy filter first: strip secrets, API keys, and `<private>...</private>`
   blocks before anything is persisted. Watch specifically for provider-key prefixes
   (e.g. `sk-`, `ghp_`/`ghu_`, `xoxb-`/`xapp-`, `AKIA...`), `-----BEGIN...PRIVATE KEY-----`
   blocks, and generic `password=`/`secret=`/`token=` assignments -- name-only, never the
   value, same as any other credential this skill already treats as unsafe to persist.
2. Append a structured entry to the daily note: `## HH:MM -- <topic>`, 3 lines max, plus
   `[[links]]`. Default `tier: trace` / `scope: session`.
3. Decisions get the schema above. When a write is also a handoff, set `handoff-to:`.

## ROUTER
`memory/index.md` carries a generated block between `<!-- GENERATED:router -->` and
`<!-- /GENERATED:router -->`, produced by `scripts/gen-router.sh` from each note's
`keywords` / `related` / `description`. Never hand-edit inside the markers.

## PROMOTION (the knowledge-manager's job)
- `tier: trace` -> `policy` when an observation recurs across >=2 sessions; -> `fact` when
  cross-task validated.
- `scope: session` -> `project` / `user` when a daily fact proves durable.
- Split a topic into its own folder plus router entry when ANY holds: >=3 durable notes; a
  note > 800 lines with separable subtopics; or multiple agents repeatedly need one slice.
- Optional `memory/promotion-candidates.base` (Obsidian Bases: `filters:
  file.inFolder("memory/daily")`, `groupBy: topic`, `Unique` summary) gives a one-glance
  topic-to-count table, additive to ripgrep, not a replacement.

## ESCAPE HATCH
To point at a heavier backend later (vector store, code graph), see
`docs/OPTIONAL-TOOLS.md`. The markdown vault stays the default.

Self-test: every vault write ran the privacy filter and appended (never overwrote).
