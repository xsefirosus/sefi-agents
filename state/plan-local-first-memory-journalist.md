## Objective

Release Sefi-Agents v0.8.0 with a private, local-first **Memory Journalist** that writes one
structured note per substantive work session, supports explicit opt-in cross-project
retrieval, and never publishes runtime memory. Add the complementary UI, codebase mapping,
repository adoption, lifecycle receipt, recovery, and behavior-conformance capabilities
validated by the exhaustive seven-repository review, without adding a required paid model,
service, vector database, browser renderer, or runtime dependency.

Use **Approach A: one integrated v0.8.0 release**. It has one migration, one history rewrite,
and one documentation cut, but creates a larger integration/review surface. The rejected
alternative is **Approach B: Memory Journalist in v0.8.0 and research/design capabilities
in v0.9.0**; it lowers each release's risk but requires two adapter/release migrations and
leaves a temporary half-state where the documented agent roster and memory workflow diverge.

Public contracts:

- Commands: `/sefi:init`, `/sefi:close-session`, `/sefi:cross-memory enable|disable|status`,
  `/sefi:memory-search <query> [--project <slug>]`, `/sefi:memory-index rebuild|status`,
  `/sefi:map-codebase <mode> [target]`, and `/sefi:scout <source>... [--plan <path>]
  [--visual]`.
- Memory config defaults: `vault_dir: memory`, `cross_project_enabled: false`, and
  `cross_project_folder_name: sefi-memory`.
- Session note path:
  `memory/sessions/YYYY/MM/YYYY-MM-DD-HHmm-two-or-three-word-title.md`.
- Session note frontmatter is fixed to `title`, `created-at` (ISO-8601), `project`,
  `session-id`, `status` (`completed|partial|blocked`), `keywords`, `related-projects`,
  `related-notes`, and `managed-by: sefi-agents`. The filename title is a lowercase
  kebab-case slug derived from a factual two-or-three-word session title.
- Required session-note sections: Context Summary, Result, Useful Information, Why This
  Happened, Files Modified, Benefits, Tradeoffs and Limits, and Follow-up. Missing factual
  content is written as `None` or `Not applicable`; raw conversations, hidden reasoning,
  command dumps, diffs, and secret values are forbidden.
- Lifecycle states: `queued`, `running`, `completed`, `failed`, `cancelled`, and
  `needs-attention`; failure classes distinguish `routing`, `model`, `tool`, `validation`,
  `permission`, `timeout`, and `internal`.

## Steps

- [ ] 1. Define and validate the shared contracts before behavior changes: Memory Journalist frontmatter/section schema; two-or-three-word filename rule; project slug from credential-stripped Git owner/repository with sanitized absolute-path fallback; harness session ID with a generated UUID-plus-UTC-start fallback persisted in ignored `.sefi/current-session`; privacy filter; cross-memory config; disposable memory-index manifest with source hashes/cursors; code-map JSON IR with typed nodes, closed relationships, evidence and freshness; adoption-candidate schema; lifecycle/failure enums; and rule-presence fixtures. Markdown remains authoritative and generated indexes/caches remain local and disposable. (needs: -)
- [ ] 2. Rename `knowledge-manager` to internal slug `memory-journalist` and display name **Memory Journalist** across the agent file, orchestration route, roster, skills, close-out behavior, templates, validators, installers, adapter transforms, generated counts, documentation references, and migration logic. Upgrade cleanup may remove an old installed file only when it carries Sefi's managed marker; user-owned files are preserved. (needs: 1)
- [ ] 3. Implement the session journal pipeline: collect other agents' factual nominations under ignored `.sefi/journal/<session-id>/`; use per-session locks, monotonic cursors, temporary files, file and directory flushes, and atomic rename; have `/sefi:close-session` privacy-filter and consolidate all substantive work in that session into exactly one structured note; make repeated closes idempotent; retain the source buffer until the note and router update are durable; recover unfinished prior buffers at the next SessionStart; and write no note for greetings, simple factual replies, status checks, or casual short chats. (needs: 1,2)
- [ ] 4. Implement local retrieval and optional cross-project memory: default cross-project memory off; prompt during interactive `/sefi:init` and choose off noninteractively; implement enable/disable/status; mirror the same filtered note under `~/sefi-memory/<project-slug>/` only on a positively identified persistent local machine and always skip CI, containers, cloud sandboxes, or unknown environments; reject unsafe paths, symlinks, credential-bearing remotes, and unnamed-project scans; implement dependency-free `rg` search followed by authoritative note reads, ranked as exact title/keyword hits, then project/related-note hits, then body hits, with newest note only as a tie-breaker; implement `/sefi:memory-index rebuild|status` with hash/cursor staleness and corruption recovery so the index can be deleted and rebuilt without changing Markdown notes. (needs: 1,3)
- [ ] 5. Wire onboarding consistently across Claude Code, Codex, OpenCode, and Hermes: after install, say installation succeeded, `/sefi:init` must run from each project root, automatic init is unsafe because installation is user-wide, and cross-project memory is optional/local/off by default; show the same concise message once on the first routed request in an uninitialized project; ensure root `/memory/` is ignored and excluded from every publisher while `plugins/sefi-core/templates/memory/` remains shipped; keep OpenCode/Hermes interactive tiers flexible, keep the scheduled OpenCode examples on `opencode/muse-spark-1.3-contributor-free`, and do not attach the paid-model preflight gate to those free workflows. (needs: 2,3,4)
- [ ] 6. Extend the existing UI/UX designer and frontend-design skill without adding a general design agent: add `PROTOTYPE` with three genuinely different isolated variants and a keyboard-accessible one-at-a-time picker; add motion discovery/plan/audit/review with purpose, frequency, exact timing, easing/spring, interruption, transform origin, reduced motion, hover-on-touch prevention, performance, Before/After/Why evidence, and rejected candidates; add mobile safe-area/viewport/touch/direct-manipulation guidance; add dependency-aware single-library recommendation that still requires approval before a new dependency; and allow an optional local visual workbench for complex prototypes. (needs: 1)
- [ ] 7. Add `research-codebase-cartographer.md` with internal agent `codebase-cartographer`, read-only source access, and writes limited to `state/codebase-map-<slug>.md`, its companion JSON IR, and an optional rendered artifact/receipt. Support MAP, TRACE, IMPACT, DELTA, and VISUALIZE; use deterministic local structure first and optional meaning second; require source paths/line ranges, content hashes, confidence and `pending|stale|ready` freshness; expose only the closed edge vocabulary `contains|imports|calls|reads|writes|emits|subscribes|depends_on|routes_to`; produce bounded maps/blast reports and likely-test evidence; render only when explicitly requested or when at least four nodes and three non-containment edges make relationships hard to scan; use an installed graph tool only when fresh, otherwise fall back to Git/`rg`; use optional Archify rendering with receipts or validated Mermaid; keep caches ignored. (needs: 1)
- [ ] 8. Add `research-adoption-scout.md` with internal agent `adoption-scout` and route repository-adoption work through Cartographer, Scout, then Product Manager. Inventory every non-`.git` file; fully read every textual code/test/prompt/schema/config/documentation file; hash and classify binary/assets without semantic claims; reconcile coverage counts; inspect entrypoints, execution/failure paths, tests, CI, release, licenses and notices; write evidence to `state/adoption-<date>-<slug>.md`; decide `Adopt|Defer|Reject` using demonstrated Sefi gap, evidence, role distinctness, privacy, dependency cost, provenance, reversibility and measurable checks; never copy, import, add dependencies, edit targets, or edit the plan directly. Product Manager appends accepted candidates only. (needs: 7)
- [ ] 9. Add local orchestration durability: write content-free atomic receipts under ignored `.sefi/runs/<session-id>/` containing task ID, agent, tier, input/output paths and hashes, lifecycle state, timestamps, route-check result, failure class and retry count; expose bounded completion/needs-attention summaries; add deterministic continuation records only for an explicit active goal or pending plan step; stop on completion, cancellation, user steering, repeated failure, budget limit, or approval boundary; never convert ordinary chat into sustained work; add installed-package manifests with relative paths/hashes and drift diagnostics while preserving user-owned files. (needs: 1,2)
- [ ] 10. Add progressive-load and clean-room behavior conformance: load new UI/cartography/scout skills only for matching routes or explicit invocation; add synthetic offline fixtures for inspect-before-act, plan/execute separation, task persistence, meaningful progress updates, clarification discipline, untrusted-content isolation, uncertainty labels, verification-before-completion, language matching, bounded parallelism and approval boundaries; prohibit copied vendor prompts/tool schemas; record exact reviewed commits and applicable licenses/notices in credits. (needs: 5,6,7,8,9)
- [ ] 11. Update the README, installation guide, all four adapter guides, command help, privacy/security guidance, optional-tools guide, migration guide, changelog, release ledger, public-boundary rules, and v0.8.0 release notes. Explain one-note-per-session behavior, explicit close/recovery, cross-memory privacy, derived-index rebuilding, new agents, optional connectors, offline defaults, and the limits of public-history deletion. (needs: 5,6,7,8,9,10)
- [ ] 12. Run and repair the complete local/offline validation matrix: note schema/naming/grouping/casual exclusion/privacy/atomicity/cursor/recovery/idempotency; local/cross retrieval and index rebuild; four-harness installs and migrations; UI prototype/motion/mobile/library rules; Cartographer evidence/freshness/fallback/delta/visual threshold; Scout coverage/provenance/immutability; lifecycle receipts/continuation stops/package drift; conformance fixtures; generated counts; links; packaging; public boundary; and the existing full CI suite. Do not invoke live providers. (needs: 3,4,5,6,7,8,9,10,11)
- [ ] 13. Prepare and publish v0.8.0 only after Step 12 passes: use a fresh mirror clone to remove repository-root `memory/` from every branch and tag while preserving plugin templates; verify every rewritten ref, tag, package and release artifact locally; force-push rewritten branches/tags; reconcile GitHub Releases; bump every version surface from 0.7.2 to 0.8.0; publish the release; verify the public repository; and document that independent forks, clones, caches and downloads cannot be erased remotely. (needs: 12)

## Files Touched

`plugins/sefi-core/agents/`; `plugins/sefi-core/skills/`; `plugins/sefi-core/commands/`;
`plugins/sefi-core/templates/`; `plugins/sefi-core/scripts/` and offline CI fixtures;
`plugins/sefi-core/config/`; all four `adapters/`; installers and publisher manifests;
`README.md`; `Install.md`; `docs/`; `CHANGELOG.md`; `CREDITS.md`; release/version ledgers;
root `.gitignore`; Git branches, tags, and GitHub Release metadata during the final step.

## Requires Tools

`git`; `git-filter-repo`; `gh`; `bash`; `python` 3.11+; `rg`; `node`; `npm`. Optional
connectors: `graft`, `archify`, and a Mermaid-capable viewer. Optional connectors are not
required for the default tests or runtime.

## Risks

The full premortem is `state/premortem-local-first-memory-journalist.md`. Its largest hidden
assumption is that all four harnesses expose enough stable session identity/lifecycle data
for one-note-per-session behavior; explicit `/sefi:close-session`, fallback IDs, cursor-based
recovery, and idempotency tests are therefore mandatory. The plan has no fatal flaw while
those fallbacks remain. The highest-impact operation is the all-ref history rewrite: rehearse
it in a fresh mirror, verify templates and every ref, and discard the mirror on any mismatch
before a force-push. System-prompt collections have uncertain per-file provenance, so only
independently authored behavior-level contracts may ship. No binary, renderer, shader, font,
image, vendor prompt, or third-party code enters Sefi without separate verified permission.

## Done Criteria

`bash plugins/sefi-core/scripts/validate-plan-structure.sh --file state/plan-local-first-memory-journalist.md`
passes; `bash plugins/sefi-core/scripts/ci/run-all.sh` passes locally with no live provider
calls; all new focused offline suites pass; fresh installs for Claude Code, Codex, OpenCode,
and Hermes contain the correct agents, commands, messages and source-manifest hashes; one
substantive fixture session produces exactly one privacy-filtered note and a casual fixture
produces none; cross-project reads require an enabled setting and explicit project; deleting
the derived index followed by rebuild yields the same search corpus; every map/scout claim has
fresh source evidence; every dispatch receipt validates without prompt content; `git log --all
-- memory` is empty after the rewrite while `plugins/sefi-core/templates/memory/` remains in
every required release ref; all version surfaces report `0.8.0`; and the public `v0.8.0`
GitHub Release points at the verified rewritten tag.
