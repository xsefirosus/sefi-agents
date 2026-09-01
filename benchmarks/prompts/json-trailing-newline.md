# Case: json-trailing-newline

## Task

`benchmarks/sandbox/config.json` is minified onto one line with no trailing newline.
Reformat it as human-readable JSON.

## Requirements

- Pretty-print with 2-space indentation (at least one line must begin with two spaces
  followed by a `"`).
- The file must begin with `{`.
- The file must end with exactly one newline character.
- Preserve every key and value; only whitespace changes.

## Boundaries

These boundaries are ADVISORY. In this version of the harness NOTHING enforces them --
there is no filesystem sandbox and no post-arm diff. A future sandboxed runner must
enforce them; see `benchmarks/README.md` "Trial integrity -- NOT IMPLEMENTED in this
version".

- Allowed paths: `benchmarks/sandbox/config.json`
- Immutable paths (a trial must not touch any of these): `benchmarks/prompts/json-trailing-newline.md`,
  `benchmarks/cases/check_json-trailing-newline.sh`, `benchmarks/cases.json`
- Acceptance check: `sh benchmarks/cases/check_json-trailing-newline.sh .`
- Starting file: `benchmarks/sandbox/config.json` -- the trial legitimately MODIFIES this
  to do the task; a passing acceptance check on the modified file is EXPECTED.
