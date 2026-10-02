# Evidence index

This is a bounded, sanitized handover from the original-plan review performed on 2026-10-01. Evidence is a snapshot, not a live guarantee. Refresh remote state before execution. The new handover plan's independent review remains PENDING; do not confuse it with the earlier original-plan conformance review.

## Included evidence

All selected artifacts are in [audit-evidence](audit-evidence). The full [audit report](audit-report.md) provides requirement matrices and source/command provenance.

| Group | Files | Meaning |
|---|---|---|
| Source identity | remote-tags.txt, tag-object.txt, tag-version-fields.json, public-marketplace-main.json | Recorded tag/ref/version observations; annotated tag-object and peeled commit differ |
| Release/public state | release-v0.9.5.json, release-list.txt, pr19-current.json, pr17.json, pr18.json | Recorded public release and PR facts |
| CI | tag-run-list.json, tag-check-runs.json, tag-status.json, pr17-head-run-list.json, pr18-head-run-list.json, runs-153.json, current-main-runs.json | Earlier green heads, no exact-tag checks, failed later main/evidence runs |
| Hosted excerpts | pr17-ci-key-lines.txt, ci-153-failed-key-lines.txt, current-main-ci-failed-key-lines.txt | Selected factual terminal results; not complete logs |
| Token replay | token-{tag,main,pr19}.{log,exit} | Tag/main 10882 fail; PR19 10877 pass against 10880 |
| Ledger replay | ledger-{153,main,pr19}-{default,strict}.{log,exit} | Included exact-source replays pass 6/6 in both modes |
| Released source/process extracts | tag-behavior-extract.txt, tag-installer-extract.txt, tag-metrics-extract.txt, post-pr18-to-tag-commits.txt, ledger-semantics.txt, ledger-v095-context.txt | Deterministic-vs-model boundary, recorded process outcomes, later changes and inaccurate ledger prose |
| Original review checks | verdict.md, report-validation.log | Prior original-plan verdict/format checks only; a citation checker checking zero citations is not semantic verification |

The original review's tag/58d ledger replay logs and full hosted logs are not included. The report labels their historical results separately. Reproduce them from immutable commits/public runs if needed; no private path is required.

## Public replay sources

- [PR17](https://github.com/xsefirosus/sefi-agents/pull/17) and its [green run 36424905130](https://github.com/xsefirosus/sefi-agents/actions/runs/36424905130).
- [PR18](https://github.com/xsefirosus/sefi-agents/pull/18) and its [green run 36463494557](https://github.com/xsefirosus/sefi-agents/actions/runs/36463494557).
- [PR19](https://github.com/xsefirosus/sefi-agents/pull/19) and [green run 36848020529](https://github.com/xsefirosus/sefi-agents/actions/runs/36848020529).
- [Evidence commit CI 36771550621](https://github.com/xsefirosus/sefi-agents/actions/runs/36771550621), failed.
- [Recorded main CI 36771691451](https://github.com/xsefirosus/sefi-agents/actions/runs/36771691451), failed.
- [Published release](https://github.com/xsefirosus/sefi-agents/releases/tag/v0.9.5).
- [Release tree](https://github.com/xsefirosus/sefi-agents/tree/2fe3bb348977a3837a8ef1fb82197afa537d1200), [evidence tree](https://github.com/xsefirosus/sefi-agents/tree/153a7298133d825d0fd2d2fc4a7087e622eadfc3), [recorded main tree](https://github.com/xsefirosus/sefi-agents/tree/e75f6f94d7b664a145753443d26cfe5d2942970b), and [PR19 tree](https://github.com/xsefirosus/sefi-agents/tree/e40785633f83c7e20db76c7a06014215aec06cad).

## Historical records

The original reviewer found historical user authorization to implement the corrected plan, including its conditional publication sequence, in a factual local session record dated 2026-09-27, with subsequent continuation instructions. Private session text and its local file are intentionally excluded. Publication is not classified as unauthorized. Complete per-dispatch owner/budget/override/retry receipts and final live/review evidence remained partial or UNVERIFIED within the inspected boundary. Recoverable records must be checked; unavailable ones must not be invented.

Selected public/source extracts were copied as UTF-8/LF with trailing whitespace removed. Historical Windows profile fixture literals were redacted to <windows-profile-fixture>; retrieve the exact original source from the immutable public tree if required. Any machine-home path was replaced with `<private-home>`; no raw session, private memory, credential, or ignored production audit was included. The original user plan is preserved as supplied, with only encoding/line-ending normalization. Check the payload against [SHA256SUMS](SHA256SUMS).
