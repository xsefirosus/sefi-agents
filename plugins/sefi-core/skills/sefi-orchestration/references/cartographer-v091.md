# Cartographer v0.9.1 contract

Use this reference only for an explicit repository map, trace, impact, delta, visual, or
context request. It governs Cartographer artifacts; it does not authorize source edits,
plans, memory writes, connector setup, network activity, commits, or publication.

## Scope and artifacts

The target source remains read-only. The only authoritative outputs are
`state/codebase-map-<slug>.md` and `state/codebase-map-<slug>.json`. Local derivatives may
exist only under `.sefi/cartographer/<slug>/`: `manifest.json`, `unresolved.json`,
`candidate-map.json`, `incremental-diagnostics.json`, `packet-*.md`, `viewer.html`, and
`connector-receipt.json`; reusable local cache may exist under
`.sefi/cartographer/cache/<slug>/`. Never overwrite an authoritative map unless all gates
pass. Never expose absolute local paths.

## Map and source evidence contract

The JSON schema is `sefi-codebase-map/v2`. It records project slug; baseline commit and
dirty-tree state; baseline relationship; target-scoped changed paths; private
`worktree_id`; inventory hash; map status; files; nodes; relationships; evidence;
subsystems; unresolved relationships; dynamic boundaries; likely tests; delta; and
optional connector and packet-manifest references. A v1 input may be normalized for
reading only; never rewrite a user-owned v1 map automatically.

Each source evidence record has a stable ID, repository-relative safe path, inclusive
line range, SHA-256 hash of selected source text, baseline, origin, derivation,
confidence, and optional map or node references. Normalize line endings to LF before
hashing selected evidence, with no other whitespace normalization. Origins are `git-rg`,
`graft`, `codegraph`, `cartographer`, `direct-repo`, or `user-supplied`; derivations are
`observed`, `imported`, or `heuristic`.

Each file has its repository-relative safe `path`, indexed and current `content_hash`, `structural_hash`, classification,
freshness, freshness reason, and last checked baseline. Each node has stable ID, type,
name, subsystem, evidence IDs, confidence, and freshness. Each relationship has endpoints,
one allowed type, evidence IDs, confidence, freshness, and derivation. Accept only
`contains`, `imports`, `calls`, `reads`, `writes`, `emits`, `subscribes`, `depends_on`, and
`routes_to`. Reject unsafe paths, malformed hashes, missing required fields, dangling IDs,
unknown edge types, invalid classifications, invalid baseline relationships, and unsupported
schema versions. Heuristic candidates remain unresolved or dynamic boundaries until current
source evidence verifies them.

## Baseline, fingerprints, and refresh

Record a hashed `worktree_id` derived from resolved worktree root and Git common directory;
never publish either absolute path. Verify worktree identity, repository root, common Git
directory, baseline, dirty state, and sorted inventory before reuse. The baseline relation is
`same, behind, ahead, diverged, or unknown`. A mismatched worktree ID or connector index is
`stale`: do not reuse its line evidence or silently redirect to that worktree; create a new
map for the current worktree. Reuse only `same` data after inventory and dirty
checks; incrementally refresh `behind`; require explicit base or clean rebuild for `ahead` and
`diverged`; fail safely and require rebuild for `unknown`. Dirty changes remain distinct from
ancestry. Record repository ancestry and target-scoped changes separately so sibling
monorepo changes do not stale the target.

`content_hash` is SHA-256 of file bytes. `structural_hash` is SHA-256 of sorted normalized
graph facts: node type, name, owner, signature, export state, imports, exports, verified
relationships, routes, calls, reads, writes, events, subscriptions, dependencies, and
subsystem membership. Exclude lines, formatting, comments, and excerpts. Classify files as
`unchanged`, `content-only`, `structural`, or `unknown`; treat `unknown` as structural.
Binary files receive metadata and content hashes only. Content-only refreshes hashes, ranges,
excerpts, packets, impact state, and affected evidence while retaining verified topology. It
still reports the implementation as changed and never establishes behavioral safety. A
structural or unknown change reprocesses relevant topology, invalidates dependent evidence,
retries affected uncertainty, recalculates subsystems/tests, and regenerates derivatives.

File freshness is `ready, pending, stale, or missing`. Warn before stale or pending evidence;
never present an old excerpt as current. Read and hash current source when safe, otherwise omit
the excerpt and name the needed file. If source changes during processing, mark the candidate
stale and stop. A successful incremental map must normalize identically to a clean rebuild.

## Symbol-loss and uncertainty gates

Run the symbol-loss gate before incremental publication. For every missing node, relationship,
or subsystem membership in a changed file, establish deletion, rename, movement, or replacement
from current source and Git evidence; match moves by type, owner, signature, relationships, and
current evidence. Retry uncertain files once with full-file inspection, then reconcile and
validate again. A verified deleted file permits removal. If loss remains unexplained, preserve
authoritative maps and cache, write `candidate-map.json` plus safe
`incremental-diagnostics.json`, return `needs-attention`, and never call the candidate current.

`unresolved.json` records stable ID, source node, reference name, expected relationship type,
source path/line/hash, status (`pending`, `resolved`, or `dismissed`), candidates and
confidence, attempts, first/last baseline, and reason. No evidence creates no relationship.
Retry only records affected by source change. Resolution creates an ordinary evidenced edge;
removed sources remove their records; repeated failure remains visible. Deleting the local
`unresolved.json` ledger never changes the authoritative map.

For an untraceable boundary, record source node and call-site evidence, boundary kind, reason,
candidate continuations, confidence, and recommended verification. Boundary kinds are
`callback, event, interface-dispatch, reflection, framework-runtime, or unknown`. Candidates
never become verified edges without current source evidence.

## Modes and context

MAP inventories current evidence. TRACE follows verified edges from the named target. IMPACT predicts possible effects before implementation. DELTA reports actual changes after implementation, comparing `--base` or prior map baseline; return `PENDING` if neither exists.
DELTA reports changed nodes, added/removed relationships, invalidated evidence, uncertainty,
affected subsystems, likely tests, predicted impacts that occurred or did not, unexpected
impacts, and remaining boundaries. Test existence never means a test passed.

CONTEXT produces deterministic local packets for Product Manager, Adoption Scout, Software
Engineer, Technical Writer, and QA. Group by requested target, verified connectivity,
subsystem, then directory proximity. The packet manifest names source map/hash, worktree and
baseline, budget and estimate method, packet paths/hashes, included files and detail levels,
redactions/exclusions, stale/pending files, uncertainty, boundaries, oversized evidence, and
time. Use `estimated tokens = ceiling(UTF-8 byte count / 2)` and label counts estimates.

Each file gets exactly one detail level: `full, structural, directory-only, or excluded`.
Exclude unsafe, escaped, unreadable, and explicitly excluded paths. Include named files, entry
points, changed files, critical trace nodes, and affected tests in full; reachable support is
structural; unrelated/generated/vendored/binary content is directory-only. Keep packets within
the budget, generate at most eight, never split a symbol or evidence excerpt, and degrade full
to structural to metadata while recording omissions. Return `PENDING` when required content
cannot fit. Packets are derivatives, never maps.

## Privacy, connectors, and visual output

Before every artifact write and before atomic replacement, scan maps, packets, candidates,
diagnostics, claims-adjacent receipts, connector receipts, and viewer content for private-key
blocks, common provider-token prefixes, credential-bearing URLs, password/token/secret/API-key
assignments, and existing Sefi patterns. Replace safely isolated values with
`[REDACTED:credential]`; exclude private-key blocks and ambiguous multiline findings. Record
only path, line, rule ID, and action, never the match. Fail closed if suspicious content remains.
The scanner reduces accidental exposure; it cannot guarantee detection.

Git and `rg` are authoritative. Use Graft or CodeGraph only when explicitly named. Graft may
import a richer local graph after recording version/source state and normalizing supported facts;
invalid or absent data falls back to Git and `rg`. CodeGraph is only targeted TRACE, IMPACT,
DELTA, CONTEXT, or boundary enrichment: confirm command response/version/current-worktree index,
use documented JSON output, reject stale/mismatched/unindexed projects, and import only
supported callers, callees, impacts, affected tests, and symbol relationships. Mark imported
facts `codegraph`, preserve direct-versus-heuristic provenance, and treat pending-sync files
as stale. Never install or initialize CodeGraph, alter telemetry, or start network activity.
Invalid CodeGraph input falls back to Git and `rg`. Only Cartographer promotes connector facts
to a map.

VISUALIZE may create `.sefi/cartographer/<slug>/viewer.html`. It is a single offline file with
embedded data, JS, and CSS; no server, dependency, or network; no remote assets or tracking; a
restrictive CSP; escaped repository content; keyboard navigation and visible focus. It filters
subsystem, type, confidence, freshness, origin, and derivation; distinguishes verified edges
from unresolved boundaries; shows paths, ranges, hashes, rationale, provenance, and stale state.
Mermaid remains the portable Markdown fallback. The viewer is disposable, never authoritative.
