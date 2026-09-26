#!/usr/bin/env bash
# Slice-4 regression checks for ignored-local audit report boundaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"

fail=0
ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; fail=$((fail + 1)); }
contains() { grep -Fq "$2" "$1" && ok "$3" || bad "$3"; }

echo '=== local audit boundary ==='
contains "$ROOT/.gitignore" '/audits/' 'root ignores audit reports'
contains "$CORE/commands/init.md" 'templates/audits/' 'init copies the audit scaffold'
contains "$CORE/commands/init.md" 'without overwriting an existing file' 'init is idempotent'
[ -f "$CORE/templates/audits/.gitkeep" ] && ok 'audit scaffold template exists' || bad 'audit scaffold template exists'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sefi-audit-integration.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/project"
mkdir -p "$WORK/config" "$WORK/memory/sessions/2026/09" "$WORK/audits"
cat > "$WORK/config/sefi.config.yml" <<'YAML'
memory:
  vault_dir: memory
  cross_project_enabled: false
  cross_project_folder_name: sefi-memory
YAML
printf '%s\n' 'durable session note' > "$WORK/memory/sessions/2026/09/session.md"
printf '%s\n' 'durable audit finding' > "$WORK/audits/audit-report-build-2026-09-25-1200-session-001.md"
printf '%s\n' 'durable non-report' > "$WORK/audits/notes.md"
git -C "$WORK" init -q
git -C "$WORK" remote add origin 'https://github.com/acme/audit-project.git'

(
  cd "$WORK"
  search_out="$(bash "$CORE/scripts/memory-search.sh" 'durable')"
  printf '%s\n' "$search_out" | grep -qx 'audits/audit-report-build-2026-09-25-1200-session-001.md'
  ! printf '%s\n' "$search_out" | grep -q 'audits/notes.md'
  bash "$CORE/scripts/memory-index.sh" rebuild >/dev/null
  grep -q 'audits/audit-report-build-2026-09-25-1200-session-001.md' .sefi/memory-index/manifest.json
  ! grep -q 'audits/notes.md' .sefi/memory-index/manifest.json
  printf '%s\n' 'changed audit finding' >> audits/audit-report-build-2026-09-25-1200-session-001.md
  ! bash "$CORE/scripts/memory-index.sh" status >/dev/null 2>&1
  bash "$CORE/scripts/memory-index.sh" rebuild >/dev/null

  local_bin="$TMP/local-bin"
  local_home="$TMP/local-home"
  mkdir -p "$local_bin" "$local_home"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" none\n' > "$local_bin/systemd-detect-virt"
  chmod +x "$local_bin/systemd-detect-virt"
  local_env=(env -u CI -u GITHUB_ACTIONS -u CODESPACES -u IS_SANDBOX PATH="$local_bin:$PATH" HOME="$local_home")
  mirror_with_confirmed_host() {
    "${local_env[@]}" bash -c '
      source_file="$1" note="$2"
      set -- status
      source "$source_file" >/dev/null
      HERE="$(cd "$(dirname "$source_file")" && pwd)"
      is_confirmed_local_machine() { return 0; }
      mirror_note "$note"
    ' _ "$CORE/scripts/memory-cross-memory.sh" "$1"
  }
  "${local_env[@]}" bash "$CORE/scripts/memory-cross-memory.sh" enable >/dev/null
  mirror="$(mirror_with_confirmed_host memory/sessions/2026/09/session.md)"
  [ -f "$mirror" ]
  ! mirror_with_confirmed_host audits/audit-report-build-2026-09-25-1200-session-001.md >/dev/null 2>&1
  ! mirror_with_confirmed_host audits/../audits/audit-report-build-2026-09-25-1200-session-001.md >/dev/null 2>&1

  # Containment must not follow a configured vault or sessions symlink outside the
  # project, even when the destination holds regular Markdown.
  external="$TMP/external"
  mkdir -p "$external/vault/sessions" "$external/sessions" regular-vault
  printf '%s\n' 'external vault note' > "$external/sessions/outside.md"
  printf '%s\n' 'nested external vault note' > "$external/vault/sessions/outside.md"
  ln -s "$external/vault" symlink-vault
  [ -L symlink-vault ]
  sed -i 's/^  vault_dir: .*/  vault_dir: symlink-vault/' config/sefi.config.yml
  ! mirror_with_confirmed_host symlink-vault/sessions/outside.md >/dev/null 2>&1

  ln -s "$external/sessions" regular-vault/sessions
  [ -L regular-vault/sessions ]
  sed -i 's/^  vault_dir: .*/  vault_dir: regular-vault/' config/sefi.config.yml
  ! mirror_with_confirmed_host regular-vault/sessions/outside.md >/dev/null 2>&1

  ln -s "$external" vault-parent
  [ -L vault-parent ]
  sed -i 's/^  vault_dir: .*/  vault_dir: vault-parent\/vault/' config/sefi.config.yml
  ! mirror_with_confirmed_host vault-parent/vault/sessions/outside.md >/dev/null 2>&1
)
ok 'audit reports are local-only, searchable, indexed, and staleness-tracked'

echo '=== audit report physical containment ==='
VALIDATOR_ROOT="$TMP/validator-root"
mkdir -p "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci" "$VALIDATOR_ROOT/audits" "$VALIDATOR_ROOT/outside"
cp "$CORE/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/"
report_body() { printf '## Summary\n## Scope\n## Method\n## Findings\nMajor finding\n## Fixes\n## Improvements\n## Nice-to-haves\n## Follow-up\n'; }
report="$VALIDATOR_ROOT/audits/audit-report-build-2026-09-26-x.md"; report_body > "$report"
bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$report" >/dev/null && ok 'valid report under audits passes' || bad 'valid report under audits passes'
outside="$VALIDATOR_ROOT/outside/audit-report-build-2026-09-26-x.md"; report_body > "$outside"
! bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/audits/../outside/audit-report-build-2026-09-26-x.md" >/dev/null 2>&1 && ok 'traversal escape fails' || bad 'traversal escape fails'
if ln -s "$VALIDATOR_ROOT/outside" "$VALIDATOR_ROOT/audits/link" 2>/dev/null; then
  ! bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/audits/link/audit-report-build-2026-09-26-x.md" >/dev/null 2>&1 && ok 'intermediate symlink escape fails' || bad 'intermediate symlink escape fails'
fi

echo '=== orphan exemption ==='
count="$(grep -Fc "! -path '*/audits/*'" "$CORE/scripts/ci/validate-no-orphans.sh" || true)"
[ "$count" -eq 4 ] && ok 'all orphan walks exempt audits' || bad 'all orphan walks exempt audits'

echo '=== scheduled loop exclusions ==='
for loop in "$ROOT"/loops/*.loop.md "$CORE"/templates/loops/*.loop.md; do
  contains "$loop" 'Never scan `audits/` on a schedule' "$(basename "$loop") excludes scheduled audit scans"
done

[ ! -e "$ROOT/run-slice4-gate-tmp.sh" ] && ok 'temporary slice-4 gate helper is absent' || bad 'temporary slice-4 gate helper is absent'

if [ "$fail" -ne 0 ]; then
  echo "test-audit-integration: $fail failure(s)" >&2
  exit 1
fi
echo 'test-audit-integration: OK'
