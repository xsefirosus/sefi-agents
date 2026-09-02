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

These boundaries are ENFORCED out-of-process by `benchmarks/runner/`: any change outside
the allowed paths makes the post-arm `snapshot.diff` non-empty, fails `integrity.verify`,
and excludes the trial from scoring. See `benchmarks/README.md` "Trial integrity --
enforced by benchmarks/runner/".

- Allowed paths: `benchmarks/sandbox/config.json`
- Immutable paths (a trial must not touch any of these): `benchmarks/prompts/json-trailing-newline.md`,
  `benchmarks/cases/check_json-trailing-newline.sh`, `benchmarks/cases.json`
- Acceptance check: `sh benchmarks/cases/check_json-trailing-newline.sh .`
- Starting file: `benchmarks/sandbox/config.json` -- the trial legitimately MODIFIES this
  to do the task; a passing acceptance check on the modified file is EXPECTED.
