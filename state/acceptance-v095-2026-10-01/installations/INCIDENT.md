# Incident note: accidental no-force installer run against the real HOME (Step 4)

At Step 4 start, a probe command containing `|` characters was executed through the
outer Windows shell, which parsed the pipes instead of passing them to git-bash.
One fragment ran `bash plugins/sefi-core/scripts/install-opencode.sh` (no flags)
from the local checkout against the REAL user HOME
(`C:\Users\Mary Rose\.config\opencode`, which already holds a sefi install).

Observed result (verbatim tool output preserved outside the repo): one
`refusing to overwrite … (use --force)` line per destination, then
`install-opencode.sh: refusing install because 86 destination(s) already exist`,
exit 1. No `transformed/copied` lines, no manifest line.

Why zero writes are certain, not hoped: the no-force preflight
(`plugins/sefi-core/scripts/install-opencode.sh:416-447`) counts every conflict
BEFORE any write and exits 1 when conflicts exist; all writes (incl `mkdir -p`,
line 462) come after. No `--force` was passed.

Remediation: after this point every command ran pipe-free; all multi-step logic
moved into script files under `C:/Users/MaryRose/s4stage/` executed as single
commands. No further out-of-scope execution occurred. Real-home state was not
modified; no commit, push, merge, version, tag, or release change was made at any
point in Step 4.
