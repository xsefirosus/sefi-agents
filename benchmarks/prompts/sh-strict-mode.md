# Case: sh-strict-mode

## Task

`benchmarks/sandbox/deploy.sh` runs without any shell strict-mode guard, so a failed
`cp` or an unset variable is swallowed silently. Add strict mode.

## Requirements

- The exact line `set -euo pipefail` must appear within the first 5 lines of the file.
- Keep the existing shebang as the first line.
- Do not change the script's behaviour otherwise.

## Boundaries

These boundaries are ADVISORY. In this version of the harness NOTHING enforces them --
there is no filesystem sandbox and no post-arm diff. A future sandboxed runner must
enforce them; see `benchmarks/README.md` "Trial integrity -- NOT IMPLEMENTED in this
version".

- Allowed paths: `benchmarks/sandbox/deploy.sh`
- Immutable paths (a trial must not touch any of these): `benchmarks/prompts/sh-strict-mode.md`,
  `benchmarks/cases/check_sh-strict-mode.sh`, `benchmarks/cases.json`
- Acceptance check: `sh benchmarks/cases/check_sh-strict-mode.sh .`
- Starting file: `benchmarks/sandbox/deploy.sh` -- the trial legitimately MODIFIES this to
  do the task; a passing acceptance check on the modified file is EXPECTED.
