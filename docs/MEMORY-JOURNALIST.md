# Memory Journalist

Memory Journalist keeps useful project context private and local. It writes one concise
Markdown note for substantial work completed during one session. It does not save casual
conversation, raw chat transcripts, hidden reasoning, secrets, terminal dumps, or full
diffs.

## Start a project

After installing Sefi-Agents, open the project root and run:

```text
/sefi:init
```

Installation is user-wide, so it cannot safely choose which project to initialize. The
command creates the ignored local `memory/` folder and asks whether to enable optional
cross-project memory. A noninteractive initialization leaves that feature disabled.

## When a note is created

All substantial work in one session becomes one note. Separate sessions create separate
notes. Greetings, casual messages, status checks, and short factual replies do not create
notes.

Run this command when you want to finish a session explicitly:

```text
/sefi:close-session
```

Repeated close requests are safe. If a session ends before its note is written, the next
session recovers the private journal buffer before continuing.

## Note layout

Notes live at:

```text
memory/sessions/YYYY/MM/YYYY-MM-DD-HHmm-two-or-three-word-title.md
```

The title contains two or three factual lowercase words in kebab case. Each note has this
frontmatter:

```yaml
title:
created-at:
project:
session-id:
status:
keywords:
related-projects:
related-notes:
managed-by: sefi-agents
```

`status` is `completed`, `partial`, or `blocked`. The body always contains these sections:

1. Context Summary
2. Result
3. Useful Information
4. Why This Happened
5. Files Modified
6. Benefits
7. Tradeoffs and Limits
8. Follow-up

When a section has no factual content, it says `None` or `Not applicable`.

## Search and rebuild

Search the current project's notes with:

```text
/sefi:memory-search <query>
```

The local search index is only a cache. Delete it at any time and rebuild it from the
Markdown source notes:

```text
/sefi:memory-index rebuild
```

## Cross-project memory

Cross-project memory is optional, local to the current OS user, and disabled by default.
Enable, disable, or inspect it from an initialized project:

```text
/sefi:cross-memory enable
/sefi:cross-memory disable
/sefi:cross-memory status
```

When enabled on a confirmed persistent local machine, filtered notes are mirrored below
`~/sefi-memory/<project-slug>/`. Sefi skips CI, containers, cloud sessions, and unknown
machines. It rejects unsafe paths, symlinks, remotes containing credentials, and unnamed
bulk scans.

Cross-project search requires both an enabled setting and an explicitly named project:

```text
/sefi:memory-search <query> --project <slug>
```

Search ranks exact title and keyword matches first, then project and related-note matches,
then note-body matches, and finally newer notes. It never scans every project in the
background.

See [Privacy](PRIVACY.md) for the data boundary and [the v0.8.0 migration guide](MIGRATION-v0.8.0.md)
when upgrading from the older memory layout.
