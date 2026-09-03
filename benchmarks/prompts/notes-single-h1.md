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

These boundaries are ENFORCED out-of-process by `benchmarks/runner/`: any change outside
the allowed paths makes the post-arm `snapshot.diff` non-empty, fails `integrity.verify`,
and excludes the trial from scoring. See `benchmarks/README.md` "Trial integrity --
enforced by benchmarks/runner/".

- Allowed paths: `benchmarks/sandbox/NOTES.md`
- Immutable paths (a trial must not touch any of these): `benchmarks/prompts/notes-single-h1.md`,
  `benchmarks/cases/check_notes-single-h1.sh`, `benchmarks/cases.json`
- Acceptance check: `sh benchmarks/cases/check_notes-single-h1.sh .`
- Starting file: `benchmarks/sandbox/NOTES.md` -- the trial legitimately MODIFIES this to
  do the task; a passing acceptance check on the modified file is EXPECTED.
