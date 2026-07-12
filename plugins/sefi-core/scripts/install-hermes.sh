#!/usr/bin/env bash
# install-hermes.sh -- install every sefi-core skill into Hermes via its native
# `hermes skills install` command. Hermes has no bulk-install verb, so this loops
# one call per skill. Agents are NOT installed this way -- Hermes has no discrete
# "install agent" concept; the roster maps to Hermes subagent delegation instead
# (delegate_task), documented separately in adapters/HERMES.md.
#
# Two skills (sefi-orchestration, security-review) are attempted with --force.
# Hermes's community-skill scanner can flag their *content* as DANGEROUS on
# substring match: sefi-orchestration's references name shell/hooks/subagent
# dispatch; security-review's checklist names dangerous patterns (eval/exec,
# curl-to-shell, unpinned installs) precisely in order to warn against them.
# On Hermes versions where --force cannot override DANGEROUS, those attempts
# fail but the script must still verify the actual installed state. The other 10
# stay on the default no-override path.
#
# The post-loop pass derives success from `hermes skills list` rather than the
# per-call exit code: hermes exits 0 even on a BLOCKED verdict, so trusting the
# exit code is the "derive success from a missing error string" anti-pattern.
set -euo pipefail

REPO="xsefirosus/sefi-agents"
BASE_PATH="plugins/sefi-core/skills"
SKILLS="sefi-orchestration anti-hallucination memory-protocol loop-engineering retro-improve terse-mode frontend-design backend-design security-review technical-writing n8n-workflow-design strategy-gate"
# Known scanner false positives; see comment above.
FORCE_SKILLS="sefi-orchestration security-review"

command -v hermes >/dev/null 2>&1 || {
  echo "install-hermes.sh: hermes CLI not found on PATH" >&2
  exit 1
}

# in_force <name> -- exit 0 if <name> is in FORCE_SKILLS.
in_force() {
  for f in $FORCE_SKILLS; do
    [ "$f" = "$1" ] && return 0
  done
  return 1
}

attempt_fail=0
for name in $SKILLS; do
  echo "=== installing $name ===" >&2
  if in_force "$name"; then
    if hermes skills install "$REPO/$BASE_PATH/$name" --yes --force; then
      :
    else
      echo "FAILED: $name (will verify installed state after all attempts)" >&2
      attempt_fail=$((attempt_fail + 1))
    fi
  else
    if hermes skills install "$REPO/$BASE_PATH/$name" --yes; then
      :
    else
      echo "FAILED: $name (will verify installed state after all attempts)" >&2
      attempt_fail=$((attempt_fail + 1))
    fi
  fi
done

echo >&2
echo "=== verifying via hermes skills list ===" >&2
if [ "$attempt_fail" -ne 0 ]; then
  echo "install-hermes.sh: $attempt_fail install call(s) failed; verifying installed state anyway." >&2
fi

# hermes skills list is a unicode-bordered table. The data lines start with
# U+2502 (vertical box char) + space; the next U+2502 + space ends the name
# column. Use awk with those patterns directly -- a tr-based collapse would map
# each byte of the multi-byte char to the same replacement (3 pipes for one
# glyph), and re-encoding the U+2502 as an ASCII byte sequence keeps this
# script ASCII-only for the repo's check-unicode-safety.sh.
vbar_sp=$(printf '\342\224\202 ')   # U+2502 + space
sp_vbar=$(printf ' \342\224\202')   # space + U+2502
installed_names=$(hermes skills list 2>&1 | awk -v lead="$vbar_sp" -v sep="$sp_vbar" '
  index($0, lead) == 1 {
    line = $0
    sub(lead, "", line)
    i = index(line, sep)
    if (i > 0) line = substr(line, 1, i - 1)
    gsub(/^ +| +$/, "", line)
    # Skip the column header row (its first column is "Name").
    if (line == "Name") next
    print line
  }
')

ok=0
missing=""
for name in $SKILLS; do
  if printf '%s\n' "$installed_names" | grep -qxF "$name"; then
    ok=$((ok + 1))
  else
    missing="$missing $name"
  fi
done

echo >&2
if [ -n "$missing" ]; then
  echo "install-hermes.sh: $ok of 12 installed. Missing:$missing. Run 'hermes doctor' and 'hermes skills list' to diagnose." >&2
  exit 1
fi
echo "install-hermes.sh: all $ok of 12 skills installed (verified via 'hermes skills list')." >&2
