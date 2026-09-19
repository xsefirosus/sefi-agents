#!/usr/bin/env bash
# Offline regression coverage for the private, local-first Memory Journalist.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures/memory-journalist"
JOURNAL="$CORE/scripts/memory-journal.sh"
SEARCH="$CORE/scripts/memory-search.sh"
INDEX="$CORE/scripts/memory-index.sh"
CROSS="$CORE/scripts/memory-cross-memory.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-memory-journalist.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WORK="$TMP/project"
mkdir -p "$WORK/config" "$WORK/memory"
git -C "$WORK" init -q
git -C "$WORK" remote add origin 'https://github.com/acme/journal-project.git'
cp "$CORE/templates/memory/index.md" "$WORK/memory/index.md"
cat > "$WORK/config/sefi.config.yml" <<'YAML'
memory:
  vault_dir: memory
  cross_project_enabled: false
  cross_project_folder_name: sefi-memory
YAML

cd "$WORK"

# A substantive nomination becomes exactly one fixed-schema note. Secret assignments and
# shell command lines are filtered before they ever reach the local buffer or final note.
bash "$JOURNAL" nominate \
  --session 'session-001' \
  --kind substantive \
  --title 'Durable Journal Recovery' \
  --status completed \
  --keywords 'journal, durability' \
  --related-projects 'journal-project' \
  --related-notes '' \
  --file "$FIXTURES/substantive.txt"
bash "$JOURNAL" close --session 'session-001'

note="$(find memory/sessions -type f -name '*.md' -print -quit)"
[ -n "$note" ] || { echo 'substantive session did not create a note' >&2; exit 1; }
[ "$(find memory/sessions -type f -name '*.md' | wc -l | tr -d ' ')" = 1 ] || {
  echo 'substantive session created more than one note' >&2; exit 1;
}
for key in title created-at project session-id status keywords related-projects related-notes managed-by; do
  grep -q "^$key:" "$note" || { echo "missing fixed frontmatter key: $key" >&2; exit 1; }
done
for section in 'Context Summary' Result 'Useful Information' 'Why This Happened' 'Files Modified' Benefits 'Tradeoffs and Limits' Follow-up; do
  grep -q "^## $section$" "$note" || { echo "missing fixed section: $section" >&2; exit 1; }
done
grep -q 'Implemented a durable local session journal with recovery.' "$note" || {
  echo 'filtered substantive fact was not retained' >&2; exit 1;
}
if grep -Eq 'should-never-be-persisted|^[[:space:]]*\$ git status' "$note" .sefi/journal/session-001/*; then
  echo 'secret or command dump reached the journal' >&2
  exit 1
fi

# A second close is idempotent and must not create a duplicate note.
bash "$JOURNAL" close --session 'session-001'
[ "$(find memory/sessions -type f -name '*.md' | wc -l | tr -d ' ')" = 1 ] || {
  echo 'repeated close created a duplicate note' >&2; exit 1;
}

# Casual activity is never buffered or journaled.
bash "$JOURNAL" nominate \
  --session 'session-casual' \
  --kind greeting \
  --title 'Friendly Status Update' \
  --status completed \
  --keywords '' \
  --related-projects '' \
  --related-notes '' \
  --file "$FIXTURES/casual.txt"
bash "$JOURNAL" close --session 'session-casual'
[ ! -d .sefi/journal/session-casual ] || { echo 'casual activity was buffered' >&2; exit 1; }
[ "$(find memory/sessions -type f -name '*.md' | wc -l | tr -d ' ')" = 1 ] || {
  echo 'casual activity created a note' >&2; exit 1;
}

# Starting a new fallback session recovers a prior unfinished substantive buffer.
bash "$JOURNAL" nominate \
  --session 'session-recovery' \
  --kind substantive \
  --title 'Pending Recovery Note' \
  --status partial \
  --keywords 'recovery' \
  --related-projects '' \
  --related-notes '' \
  --file "$FIXTURES/substantive.txt"
bash "$JOURNAL" session-id >/dev/null
[ "$(find memory/sessions -type f -name '*.md' | wc -l | tr -d ' ')" = 2 ] || {
  echo 'unfinished journal buffer was not recovered at session start' >&2; exit 1;
}

# Search ranks persisted local notes and the disposable manifest detects staleness safely.
search_output="$(bash "$SEARCH" 'durable')"
printf '%s\n' "$search_output" | grep -q 'durable-journal-recovery.md' || {
  echo 'local journal note was not searchable' >&2; exit 1;
}
bash "$INDEX" rebuild >/dev/null
bash "$INDEX" status >/dev/null
printf '{corrupt\n' > .sefi/memory-index/manifest.json
if bash "$INDEX" status >/dev/null 2>&1; then
  echo 'corrupt disposable index was accepted as fresh' >&2
  exit 1
fi
bash "$INDEX" rebuild >/dev/null
bash "$INDEX" status >/dev/null

# Cross-memory remains local and disabled until an explicit enable. A named-project
# query is still refused while disabled, preventing an unnamed or ambient scan.
if bash "$SEARCH" 'durable' --project 'journal-project' >/dev/null 2>&1; then
  echo 'cross-project search ran while cross-memory was disabled' >&2
  exit 1
fi
bash "$CROSS" status | grep -qx 'disabled'

# A confirmed local-machine fixture mirrors only the filtered note for the explicit
# credential-free project slug. The cross search requires that same named project.
LOCAL_BIN="$TMP/local-bin"
LOCAL_HOME="$TMP/local-home"
mkdir -p "$LOCAL_BIN" "$LOCAL_HOME"
LOCAL_HOME_REAL="$(cd "$LOCAL_HOME" && pwd -P)"
cat > "$LOCAL_BIN/systemd-detect-virt" <<'SH'
#!/usr/bin/env bash
printf '%s\n' none
SH
chmod +x "$LOCAL_BIN/systemd-detect-virt"
local_env=(env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX \
  PATH="$LOCAL_BIN:$PATH" HOME="$LOCAL_HOME")
"${local_env[@]}" bash "$CROSS" enable >/dev/null
"${local_env[@]}" bash "$CROSS" status | grep -qx 'enabled'
mirror="$("${local_env[@]}" bash "$CROSS" mirror "$note")"
[ -f "$mirror" ] || { echo 'enabled cross-project memory did not mirror a filtered note' >&2; exit 1; }
case "$mirror" in "$LOCAL_HOME_REAL"/sefi-memory/acme-journal-project/*) ;; *)
  echo "cross-project mirror used an unsafe or incorrect project slug: $mirror" >&2; exit 1 ;;
esac
"${local_env[@]}" bash "$SEARCH" 'durable' --project 'acme-journal-project' | grep -q 'durable-journal-recovery.md' || {
  echo 'enabled named cross-project search did not find the mirrored note' >&2; exit 1;
}
"${local_env[@]}" bash "$CROSS" disable >/dev/null
"${local_env[@]}" bash "$CROSS" status | grep -qx 'disabled'

echo 'test-memory-journalist: OK'
