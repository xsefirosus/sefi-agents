# Historical plan: Corrected systems-audit plan for v0.9.5

This is a faithful record of the historical user-supplied plan. It is not new authorization to execute, merge, tag, release, or change a version.

## Review result

**The goal remained intact, but the shortened plan lost necessary detail and contained one incorrect justification.** This replacement restores those requirements and addresses the installation gaps found during review.

| Finding | Correction |
|---|---|
| A clean report already passes when its summary records zero severity counts. | Keep the existing severity validation; remove the proposed relaxation. |
| The validator derives its project root from its installed script location. A valid report in a separate project failed the diagnostic test. | Add an explicit project-root argument and test validation from an installed package against a different project. |
| Hermes’s native installer installs skill folders without the canonical agent and validation scripts. | Extend it with canonical runtime support, as selected by the user. |
| Codex and Hermes installers fetch remote content. Running them from a feature checkout does not prove they installed that checkout. | Verify candidate installations and published installations separately, recording the actual source revision and content. |
| The shorter plan omitted detailed behavioral checks, numeric retry limits, and the final release-evidence commit. | Restore them explicitly below. |

The current documentation counts, adapter validation, token limits, and strict v0.9.4 release ledger passed. Temporary diagnostic fixtures confirmed the two validator behaviors above. Repository files remain unchanged. These results verify the current baseline and planning assumptions; they are not implementation QA for the proposed skill.

## Skill behavior and audit method

Create `systems-audit` with a concise `SKILL.md` and a linked evidence-method reference. Keep the auditor agent as the authoritative source for department criteria; the departments document remains its readable record.

- Activate for explicit Sefi department-audit intent or explicit skill invocation. Preserve ordinary UI, security, and code-review routing. Audit execution remains on demand.
- Preserve the eight scopes: `complete`, `research`, `product`, `design`, `build`, `quality`, `docs`, and `delivery`. Missing or unsupported scope prompts one clarification rather than assuming `complete`.
- The top-level orchestrator owns dispatch. The dispatched Systems Auditor loads the method and performs the audit without dispatching another agent.
- Preserve department order, core checks before appendix checks, foundational Research/Product triage, four severity levels, five displayed findings per department, and exact overflow totals.
- Keep the skill description within 60 words and its main file within 300 lines. Link every supporting reference and retain the anti-hallucination pointer. Add the auditor’s skill pointer without exceeding the aggregate agent-word limit, which currently has only 17 words of headroom.

The method must guide the auditor through:

1. **Define the audit:** identify scope, designated project root, revision, applicable criteria, expected artifacts, and exclusions.
2. **Map evidence:** connect each criterion to inspected artifacts or executed checks. Record provenance, freshness, contradictions, and limitations.
3. **Choose coverage:** assess every applicable criterion; select artifact samples according to risk and disclose what was sampled. A `complete` audit covers all seven departments but does not imply every artifact was inspected.
4. **Verify selectively:** inspect source and run bounded checks that answer concrete questions. Check commands for side effects before running them. Record command, target, outcome, and relevant evidence; use `PENDING` for unrun checks and `UNKNOWN` for unsupported conclusions.
5. **Develop findings:** cite the criterion, observed condition, evidence, severity rationale, and effect. State root cause only when supported. Keep proposed remedies separate from findings.
6. **Report accurately:** include coverage and limitations, preserve the report cap, and avoid treating an author’s claim or a structurally valid report as proof of correctness.

The reference should explain these adaptations from [ISO 19011](https://www.iso.org/standard/19011), [NIST SP 800-53A](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final), [IIA standards](https://www.theiia.org/en/standards/2024-standards/global-internal-audit-standards/), and [GAO auditing standards](https://www.gao.gov/assets/d24106786.pdf), with source links and no certification claim.

Reports retain the existing eight headings and one new file under `audits/`. Clean reports state zero severity counts and “No findings in inspected surfaces.” Preserve overwrite refusal, local storage, and explicit confirmation before fix planning. Add an `INCOMPLETE` terminal status for an inaccessible required artifact or output failure, so an unread audit cannot be reported as complete.

Extend `validate-audit-report.sh` with `--root <absolute-project-directory>`. Runtime callers must supply that root and the explicit report path. Preserve the existing default for repository CI, exit-code meanings, scope checks, and physical containment protections.

## Installation and documentation

Verify the complete invocation path on all four shipped harnesses:

| Harness | Required result |
|---|---|
| Claude Code | Native plugin and supported fallback installation include the skill, auditor, references, and validator. |
| Codex | Native installation exposes the skill in a fresh session and retains the Systems Auditor profile. Verify the documented invocation name rather than assuming slash-command migration. |
| OpenCode | Its installer includes the skill and required runtime files while preserving existing agent and permission transformations. |
| Hermes | Native skill installation also provides the canonical runtime needed to execute the auditor and validate its report. |

For Hermes, install a managed copy of the canonical plugin runtime under `sefi-core/` beside the configuration file reported by Hermes. Keep native skill discovery in Hermes’s existing skills directory. Resolve this runtime explicitly from the installed skill; pass both runtime root and audited-project root in the handoff.

The runtime copy must include the canonical agent, skills, scripts, configuration, commands, and templates needed by its references. Record its source revision and managed-file hashes. Preserve unrelated files and refuse to overwrite modified managed content silently. Extend `--auto-update` so a skill-only installation is upgraded and a missing runtime cannot be reported as current. Verify fetched skill content against the expected source before recording installation success.

Update both READMEs, relevant adapter and installation documentation, onboarding guidance, skill inventories, and affected count assertions. The resulting package has 20 skills. Explain command, skill, and agent responsibilities; valid scopes; installed invocation examples; report location; local search/index inclusion; and mirror exclusion. Avoid runtime dependencies on documentation available only in the repository checkout.

## Implementation and verification

Use three bounded slices:

1. **Skill and report contract:** method, routing references, report-root support, and behavioral verification.
2. **Harness installation and documentation:** runtime support, install/upgrade coverage, inventories, READMEs, and onboarding.
3. **Release preparation:** version metadata, changelog, release notes, and prepublication ledger entries.

Each implementation slice gets one responsible software-engineer dispatch and a separate QA verdict with rerun evidence. Before dispatch, validate the handoff and check the **$0.15 dispatch / $2.00 daily** caps. Record routes and receipts. Escalate after the **second REJECT** on a slice. Obtain a whole-branch review and a security review of the installer and project-root changes before publication.

Acceptance coverage must include:

- Explicit invocation, valid scopes, missing scope, unsupported scope, and adjacent requests retaining their normal routes.
- Foundational triage, supported findings, clean reports, contradictory evidence, missing execution evidence, and incomplete audits.
- Severity ordering, five-finding caps, overflow totals, report collisions, and confirmation before fix planning.
- Validation from an installed package against a separate project, including spaces in paths, traversal attempts, and symlink escapes.
- Fresh installation, upgrade from the existing release, repeat installation, user-modified files, missing runtime assets, and source-revision mismatch.
- Existing v0.9.4 behavior: ignored-local reports, discovery, index staleness, mirror refusal, idempotent initialization, and scheduled-loop exclusions.

Use independent behavioral scenarios before and after introducing the skill, with isolated artifacts and no expected answer supplied to the evaluating agent. Static phrase checks alone do not establish working behavior.

Run targeted regressions, repository gates, and hosted CI against the final candidate revision. Bound the known local suite stall using the existing timeout classes. Preserve `PENDING` for timed-out portions; require completed hosted evidence for the corresponding release claim. Public-install smoke checks must verify what was actually downloaded.

The current daily budget check reports `CANNOT MEASURE`. Execution must obtain genuine spend telemetry or a task-specific override before specialist dispatch; do not substitute an assumed zero.

## Publication and completion

After the user decides to execute this corrected plan:

1. Extend PR #17 and rewrite its title and description for the full feature. Reuse its README work.
2. Set both plugin manifests and both Claude marketplace version fields to **0.9.5**. The Codex marketplace has no version field to invent. Add the dated changelog entry and truthful prepublication ledger rows.
3. Finish QA, review, and CI; merge to `main` under the user’s publication authorization. Identify the tested release commit explicitly.
4. Verify installations from the public source, then create and push `v0.9.5` at that release commit and publish the GitHub release with matching notes.
5. Observe all six release surfaces directly and append final ledger evidence. Run strict ledger validation, commit the evidence, and push that follow-up commit to `main`. Keep the release tag on the original tested release commit.
6. Report the release URL, release commit, installation verification, and any remaining limitations. Use “partially released” while a required public surface remains unmatched.

The release is a new v0.9.5 continuation of v0.9.4. Existing v0.9.3 and v0.9.4 tags remain immutable.
