#!/usr/bin/env bash
# memory-filter.sh -- remove known secrets and raw command/diff dumps before journaling.
set -euo pipefail

python_bin=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
[ -n "$python_bin" ] || { echo 'memory-filter: Python is required' >&2; exit 1; }

"$python_bin" -c '
import re
import sys

secret_line = re.compile(
    r"(?:\b(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|authorization)\b\s*[:=]|"
    r"\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_-]{8,}|github_pat_[A-Za-z0-9_-]{8,}|"
    r"xox[baprs]-[A-Za-z0-9_-]{8,}|AKIA[0-9A-Z]{12,}|AIza[0-9A-Za-z_-]{20,})\b|"
    r"://[^\s/@]+:[^\s/@]+@)",
    re.IGNORECASE,
)
prompt_line = re.compile(r"^\s*(?:\$\s+|PS [^>\r\n]*>\s*|>\s+)")
diff_start = re.compile(r"^(?:diff --git\s|Index: |---\s+|\+\+\+\s|@@\s)")

private = False
fence = False
diff = False
for raw in sys.stdin:
    line = raw.rstrip("\r\n")
    if re.search(r"<private(?:\s[^>]*)?>", line, re.IGNORECASE):
        private = True
    if private:
        if re.search(r"</private>", line, re.IGNORECASE):
            private = False
        continue
    if re.search(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", line, re.IGNORECASE):
        private = True
        continue
    if private:
        if re.search(r"-----END [A-Z0-9 ]*PRIVATE KEY-----", line, re.IGNORECASE):
            private = False
        continue
    if line.strip().startswith("```"):
        fence = not fence
        continue
    if fence:
        continue
    if diff_start.match(line):
        diff = True
        continue
    if diff:
        if not line.strip():
            diff = False
        else:
            continue
    if not line.strip() or prompt_line.match(line) or secret_line.search(line):
        continue
    sys.stdout.write(line + "\n")
'
