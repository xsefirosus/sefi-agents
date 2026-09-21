# Privacy

This guide is for people deciding whether to use Sefi-Agents memory features. Runtime
memory is private by default and stays on the machine where you initialize a project.

## Default behavior

`/sefi:init` creates an ignored `memory/` folder inside the project. Sefi writes only
filtered session notes there. The published plugin contains empty memory templates, not
your runtime notes.

The journal removes secret-shaped values, credential-bearing remote URLs, private blocks,
terminal prompt lines, code fences, and diff-like content before it makes a final note.
Do not place secrets in project notes or configuration; filtering reduces accidental
retention but cannot make intentionally stored secrets safe.

## Optional cross-project memory

Cross-project memory is disabled until you explicitly enable it. It mirrors filtered notes
under `~/sefi-memory/<project-slug>/` for the current local OS user only. It does not use a
hosted database, vector database, browser renderer, or paid model.

Sefi refuses cross-project mirroring on CI, in containers, in cloud sessions, and on
unknown machines. It also rejects symlinks, unsafe paths, credential-bearing Git remotes,
and broad scans of unnamed projects. Reading another project's notes requires an explicitly
named project and a clear task connection.

## What you control

Use these commands from a project root:

```text
/sefi:cross-memory status
/sefi:cross-memory enable
/sefi:cross-memory disable
/sefi:memory-index rebuild
```

The Markdown notes are the source of truth. The index is a disposable local cache. You can
delete the index and recreate it without changing the notes.

## Repository intelligence artifacts

Codebase maps, context packets, candidate diagnostics, local viewers, documentation Claims,
and documentation manifests are created only inside the project when their matching work is
requested. The map and Claim records use repository-relative evidence and never publish an
absolute local path. Caches, packets, snapshots, and candidate files under `.sefi/` are
disposable local derivatives.

Sefi scans generated repository-intelligence artifacts for credential-shaped values before
writing them and fails closed when it cannot safely remove a finding. This reduces accidental
exposure but does not guarantee detection of every secret format. Do not put credentials in
source excerpts, documentation Claims, or user-managed project state.

## Public history

v0.8.0 removes old runtime `memory/` paths from the repository's rewritten public Git
history. A history rewrite cannot erase copies in independent forks, existing clones, Git
caches, search indexes, release archives, or files people already downloaded. Remove any
sensitive material from those copies through the service or owner that controls them.
GitHub can also retain read-only refs for merged or closed pull requests. Branch and tag
force-pushes cannot rewrite those server-managed refs; treat them as a separate GitHub
retention boundary.
