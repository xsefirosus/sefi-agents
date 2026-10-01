# Baseline: Step 2 deterministic acceptance

- Target commit: `83c89703d1ef1a1739c1f4d9807d48986632d8b8`
- Branch: `handover/v095-acceptance-remediation-20261001` (published to origin;
  Step 2 corrections uncommitted per plan).
- Host: symlink-capable Linux via Docker on a Windows host (native Windows
  cannot express the symlink-escape legs; those legs SKIP/PENDING there by
  suite design, which is not acceptance proof).
- Linux image: `sefi-acceptance:local` built `FROM py311-git:local`
  (`python:3.11`-family, git present) plus `jq` + `ripgrep` via apt.
  Repo under test is copied to Linux-native `/tmp/work` inside the container
  (Windows bind-mounts do not guarantee symlink semantics); the source mount
  is read-only.
- Tool versions: recorded per executed command in `commands.jsonl`.
- Agent word cap context: 17 agents x 640 = 10,880 words (plan Step 2
  threshold); enforced by `validate-token-budget.sh`.
- Historical reference only: PR19 installers reported 231 PASS / 0 FAIL /
  0 PENDING; counts may change if meaningful checks were added.
