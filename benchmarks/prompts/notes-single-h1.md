# Case: notes-single-h1

## Task

`benchmarks/sandbox/NOTES.md` has two level-1 headings (`# ` lines). A Markdown
document should have exactly one H1.

## Requirements

- After the change, exactly one line in the file starts with `# ` (H1).
- Keep the first H1 (`# Release notes`) as-is.
- Demote every other H1 to H2 (`## `); keep its text.
- Do not delete any section or its body.

## Boundaries

These boundaries are ADVISORY. In this version of the harness NOTHING enforces them --
there is no filesystem sandbox and no post-arm diff. A future sandboxed runner must
enforce them; see `benchmarks/README.md` "Trial integrity -- NOT IMPLEMENTED in this
version".

- Allowed paths: `benchmarks/sandbox/NOTES.md`
- Immutable paths (a trial must not touch any of these): `benchmarks/prompts/notes-single-h1.md`,
  `benchmarks/cases/check_notes-single-h1.sh`, `benchmarks/cases.json`
- Acceptance check: `sh benchmarks/cases/check_notes-single-h1.sh .`
- Starting file: `benchmarks/sandbox/NOTES.md` -- the trial legitimately MODIFIES this to
  do the task; a passing acceptance check on the modified file is EXPECTED.
