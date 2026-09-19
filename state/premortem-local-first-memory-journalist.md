# Premortem: Local-First Memory Journalist v0.8.0

The release renames the memory agent, moves runtime memory behind a local-only boundary,
adds structured session notes and optional cross-project retrieval, adds two repository
understanding agents and deeper UI skills, and rewrites every public branch/tag before a
single v0.8.0 release. Work starts only after plan approval, uses the existing specialist
chain and local/offline tests, and is done when the rewritten release and all adapters pass.

## 1. The Autopsy

1. **The release died from incomplete cross-surface wiring.** Month 1 implemented the
   agent and commands; month 2 exposed stale names and counts in adapters/installers; by
   month 3 users had different behavior by harness. The hidden assumption was that the
   current validators enumerate every published surface. The first warning was any
   `knowledge-manager` hit outside frozen history after Step 2.
2. **Session notes split or duplicated one session.** Month 1 added buffering; month 2
   harnesses supplied inconsistent session IDs; by month 3 repeated close/recovery paths
   emitted multiple notes. The assumption was that every harness offers a stable end-of-
   session identity. The warning was a duplicate finalization fixture or an unclosed buffer
   surviving two SessionStart events.
3. **The history rewrite removed product templates or broke release tags.** Month 1 used a
   path filter too broadly; month 2 force-pushed it; by month 3 fresh installs lacked memory
   templates or releases pointed to missing artifacts. The assumption was that root
   `memory/` and packaged template paths could not be confused. The warning was a mirror-
   clone verification showing any missing `plugins/sefi-core/templates/memory/` object.
4. **Cross-project memory leaked or silently stopped working.** Month 1 changed defaults;
   month 2 path and environment differences surfaced; by month 3 users either saw another
   project unexpectedly or received no mirror with no useful diagnosis. The assumption was
   that home-path, project-slug, and ephemeral-environment detection are uniform. The
   warning was any test permitting an unnamed-project scan or any enabled local fixture
   producing no explicit mirror status.
5. **The added agents increased routing ambiguity instead of understanding.** Month 1 added
   Cartographer and Scout; month 2 generic research requests began reaching the wrong role;
   by month 4 plans depended on uncited or stale maps. The assumption was that role prose
   alone prevents overlap. The warning was one routing fixture where research-analyst,
   Cartographer, and Scout all match the same intent.
6. **The release became too large to review coherently.** Month 1 parallel work produced
   independent contracts; month 2 integration exposed incompatible artifact names; month 3
   fixes changed already-reviewed steps; by month 6 no stable candidate shipped. The
   assumption was that a single v0.8.0 integration branch would remain reviewable. The
   warning was more than one contract/schema being redefined after its dependent step began.
7. **Prompt and third-party material crossed the provenance boundary.** Month 1 clean-room
   summaries were written; month 2 copied language or assets slipped into implementation;
   by month 4 release review could not prove origin. The assumption was that conceptual
   adoption is self-enforcing. The warning was any new long passage or asset without a
   source/author record and independent wording review.

## 2. The Verdict

- **MOST LIKELY:** incomplete cross-surface wiring, because the same role, command, count,
  and installer contract is repeated across four harness adapters and generated checks.
- **MOST DANGEROUS:** the history rewrite, because a bad force-push changes every public ref
  and is harder to recover than a normal release defect.
- **Biggest hidden assumption:** every supported harness can supply enough stable session
  identity and lifecycle information to uphold one-note-per-session without a native end
  hook.
- **Fatal-flaw call:** this plan has no fatal flaw if explicit `/sefi:close-session`, next-
  start recovery, and per-harness fallback IDs remain part of the contract. Removing those
  fallbacks would make the cross-harness promise unimplementable.

## 3. The Rebuild

Implement contracts and deterministic validators first; keep each capability behind its
own offline fixture; make explicit close/recovery the portable session boundary; require
freshness/evidence receipts before maps or scout candidates are accepted; integrate all
features before touching public history; rewrite in a fresh mirror; verify every ref and
template; then publish one release.

| Change | Failure closed |
| --- | --- |
| Central schema and rule-presence manifest before implementation | 1, 6 |
| Explicit close command, fallback session IDs, cursor and idempotency tests | 2 |
| Fresh-mirror rewrite plus template/ref verification before push | 3 |
| Default-off cross-memory and named-project-only reads | 4 |
| Disjoint routing fixtures and evidence/freshness gates | 5 |
| Step-scoped artifacts with dependency order and one integration gate | 6 |
| Clean-room rule plus credits/notices and public-boundary scan | 7 |

Pre-launch checks:

1. Run the full offline suite before history work; walk away from release if any adapter,
   installer, privacy, or public-boundary test fails.
2. Create a disposable four-harness install matrix; walk away if any installed copy has a
   stale agent, missing command, or mismatched manifest hash.
3. Run the rewrite against a fresh local mirror and compare every ref; walk away if any
   template disappears or any root `memory/` object remains.
4. Inspect every new attribution/public artifact; walk away if provenance is UNKNOWN for
   copied text, code, font, or image content.

## 4. The Adversary

I would attack the release boundary: trigger a stale adapter, ambiguous routing request,
and interrupted session close, then point to the inconsistent outputs as proof the four-
harness claim is unreliable. During launch week I would compare a fresh install from each
published surface and publish the first mismatch. The indirect move would be preserving an
old public tag or archive containing the supposedly removed runtime memory and using it to
undermine the privacy claim.

## 5. The Tripwires

| # | Failure mode | Signal | Check when | Threshold = act |
| --- | --- | --- | --- | --- |
| 1 | Cross-surface drift | stale-name/count hits | End of week 1 | Any non-frozen hit: pause dependent work and fix the manifest |
| 2 | Duplicate session notes | notes per closed session | End of week 2 | Anything other than 1: block integration |
| 3 | Bad history rewrite | missing templates or remaining root memory objects | Rewrite rehearsal, week 5 | Any mismatch: discard rewritten mirror |
| 4 | Cross-project leak/failure | unnamed read or silent enabled-write failure | End of week 2 | One occurrence: disable feature until fixed |
| 5 | Ambiguous routing | multi-match routing fixtures | End of week 3 | Any multi-match: rewrite routes before agent install tests |
| 6 | Integration churn | contract changes after dependent step starts | Weekly | More than 1 changed contract: freeze additions and split release |
| 7 | Provenance breach | copied artifact without verified license/source | Before release, week 5 | Any occurrence: remove artifact and rerun boundary audit |

Calendar first: the stale-name/count scan at the end of week 1.
