#!/usr/bin/env bash
# Slice-4 regression checks for ignored-local audit report boundaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CORE="$ROOT/plugins/sefi-core"
# MSYS path helper: native Windows git aborts on `git -C /c/...` with
# "cannot change to", so the fixture repo below would never be created.
# See scripts/sefi-native-path.sh.
. "$CORE/scripts/sefi-native-path.sh"

fail=0
pending_count=0
ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  BAD %s\n' "$1" >&2; fail=$((fail + 1)); }
# A host that cannot create a physical symlink (no symlink privilege, an `ln -s` that
# silently falls back to a copy, a filesystem without link support) cannot produce the
# case under test, and a BAD there would report a product regression that never ran.
# Same convention as test-systems-audit-installers.sh: the leg is PENDING and the run
# continues. A host with real symlinks still runs the assertion and still FAILs on a
# genuine regression, because the guard is `[ -L ]` (a real link), not `ln -s` (which can
# succeed while leaving a plain file or directory behind).
pending() { printf '  PENDING %s\n' "$1"; pending_count=$((pending_count + 1)); }
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
git -C "$(sefi_native_path "$WORK")" init -q
git -C "$(sefi_native_path "$WORK")" remote add origin 'https://github.com/acme/audit-project.git'

if (
  # One leg must never silence the rest: errexit stays on outside this subshell,
  # but inside every leg reports its own OK/BAD and the subshell carries the tally
  # in its exit status (a subshell cannot touch the parent's $fail counter).
  set +e
  subfail=0
  leg_bad() { bad "$1"; subfail=1; }
  # Same story as leg_bad for a leg the host cannot express: it prints its PENDING line
  # and leaves subfail alone. The count itself cannot cross back out of the subshell, so
  # the PENDING lines in the output are the tally, exactly as OK/BAD lines are read there.
  leg_pending() { printf '  PENDING %s\n' "$1"; }

  cd "$WORK" || { leg_bad 'fixture project directory is reachable'; exit 1; }

  if search_out="$(bash "$CORE/scripts/memory-search.sh" 'durable')"; then
    ok 'memory search completes for a durable query'
  else
    leg_bad 'memory search completes for a durable query'
    search_out=''
  fi
  if printf '%s\n' "$search_out" | grep -qx 'audits/audit-report-build-2026-09-25-1200-session-001.md'; then
    ok 'memory search surfaces the durable audit report'
  else
    leg_bad 'memory search surfaces the durable audit report'
  fi
  if printf '%s\n' "$search_out" | grep -q 'audits/notes.md'; then
    leg_bad 'memory search excludes non-report audit notes'
  else
    ok 'memory search excludes non-report audit notes'
  fi
  if bash "$CORE/scripts/memory-index.sh" rebuild >/dev/null; then
    ok 'memory index rebuild succeeds'
  else
    leg_bad 'memory index rebuild succeeds'
  fi
  if grep -q 'audits/audit-report-build-2026-09-25-1200-session-001.md' .sefi/memory-index/manifest.json 2>/dev/null; then
    ok 'memory index manifest includes the audit report'
  else
    leg_bad 'memory index manifest includes the audit report'
  fi
  if grep -q 'audits/notes.md' .sefi/memory-index/manifest.json 2>/dev/null; then
    leg_bad 'memory index manifest excludes non-report audit notes'
  else
    ok 'memory index manifest excludes non-report audit notes'
  fi
  if printf '%s\n' 'changed audit finding' >> audits/audit-report-build-2026-09-25-1200-session-001.md; then
    ok 'audit report edit lands for the staleness check'
  else
    leg_bad 'audit report edit lands for the staleness check'
  fi
  if bash "$CORE/scripts/memory-index.sh" status >/dev/null 2>&1; then
    leg_bad 'memory index status detects staleness after an audit edit'
  else
    ok 'memory index status detects staleness after an audit edit'
  fi
  if bash "$CORE/scripts/memory-index.sh" rebuild >/dev/null; then
    ok 'memory index rebuild succeeds after an audit edit'
  else
    leg_bad 'memory index rebuild succeeds after an audit edit'
  fi

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
  if "${local_env[@]}" bash "$CORE/scripts/memory-cross-memory.sh" enable >/dev/null; then
    ok 'cross-memory enable succeeds in the fixture project'
  else
    leg_bad 'cross-memory enable succeeds in the fixture project'
  fi
  if mirror="$(mirror_with_confirmed_host memory/sessions/2026/09/session.md)" && [ -f "$mirror" ]; then
    ok 'session note mirrors to the confirmed local vault'
  else
    leg_bad 'session note mirrors to the confirmed local vault'
  fi
  if mirror_with_confirmed_host audits/audit-report-build-2026-09-25-1200-session-001.md >/dev/null 2>&1; then
    leg_bad 'cross-memory mirror refuses an audit report'
  else
    ok 'cross-memory mirror refuses an audit report'
  fi
  if mirror_with_confirmed_host audits/../audits/audit-report-build-2026-09-25-1200-session-001.md >/dev/null 2>&1; then
    leg_bad 'cross-memory mirror refuses a traversal-shaped audit path'
  else
    ok 'cross-memory mirror refuses a traversal-shaped audit path'
  fi

  # Containment must not follow a configured vault or sessions symlink outside the
  # project, even when the destination holds regular Markdown.
  external="$TMP/external"
  mkdir -p "$external/vault/sessions" "$external/sessions" regular-vault
  printf '%s\n' 'external vault note' > "$external/sessions/outside.md"
  printf '%s\n' 'nested external vault note' > "$external/vault/sessions/outside.md"
  if ln -s "$external/vault" symlink-vault 2>/dev/null && [ -L symlink-vault ]; then
    ok 'symlinked vault fixture is a physical symlink'
    if sed -i 's/^  vault_dir: .*/  vault_dir: symlink-vault/' config/sefi.config.yml; then
      if mirror_with_confirmed_host symlink-vault/sessions/outside.md >/dev/null 2>&1; then
        leg_bad 'mirror refuses a note addressed through a symlinked vault'
      else
        ok 'mirror refuses a note addressed through a symlinked vault'
      fi
    else
      leg_bad 'fixture vault config points at the symlinked vault'
    fi
  else
    leg_pending 'mirror refuses a note addressed through a symlinked vault requires a physical symlink'
  fi

  if ln -s "$external/sessions" regular-vault/sessions 2>/dev/null && [ -L regular-vault/sessions ]; then
    ok 'symlinked sessions fixture is a physical symlink'
    if sed -i 's/^  vault_dir: .*/  vault_dir: regular-vault/' config/sefi.config.yml; then
      if mirror_with_confirmed_host regular-vault/sessions/outside.md >/dev/null 2>&1; then
        leg_bad 'mirror refuses a note addressed through a symlinked sessions dir'
      else
        ok 'mirror refuses a note addressed through a symlinked sessions dir'
      fi
    else
      leg_bad 'fixture vault config points at the regular vault'
    fi
  else
    leg_pending 'mirror refuses a note addressed through a symlinked sessions dir requires a physical symlink'
  fi

  if ln -s "$external" vault-parent 2>/dev/null && [ -L vault-parent ]; then
    ok 'symlinked vault-parent fixture is a physical symlink'
    if sed -i 's/^  vault_dir: .*/  vault_dir: vault-parent\/vault/' config/sefi.config.yml; then
      if mirror_with_confirmed_host vault-parent/vault/sessions/outside.md >/dev/null 2>&1; then
        leg_bad 'mirror refuses a note addressed through a symlinked vault parent'
      else
        ok 'mirror refuses a note addressed through a symlinked vault parent'
      fi
    else
      leg_bad 'fixture vault config points under the symlinked parent'
    fi
  else
    leg_pending 'mirror refuses a note addressed through a symlinked vault parent requires a physical symlink'
  fi
  exit "$subfail"
); then
  ok 'audit reports are local-only, searchable, indexed, and staleness-tracked'
else
  bad 'audit reports are local-only, searchable, indexed, and staleness-tracked'
fi

echo '=== audit report physical containment ==='
VALIDATOR_ROOT="$TMP/validator-root"
mkdir -p "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci" "$VALIDATOR_ROOT/audits" "$VALIDATOR_ROOT/outside"
cp "$CORE/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/"
report_body() { printf '## Summary\n## Scope\n## Method\n## Findings\nMajor finding\n## Fixes\n## Improvements\n## Nice-to-haves\n## Follow-up\n'; }
report="$VALIDATOR_ROOT/audits/audit-report-build-2026-09-26-x.md"; report_body > "$report"
bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$report" >/dev/null && ok 'valid report under audits passes' || bad 'valid report under audits passes'
outside="$VALIDATOR_ROOT/outside/audit-report-build-2026-09-26-x.md"; report_body > "$outside"
! bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/audits/../outside/audit-report-build-2026-09-26-x.md" >/dev/null 2>&1 && ok 'traversal escape fails' || bad 'traversal escape fails'
if ln -s "$VALIDATOR_ROOT/outside" "$VALIDATOR_ROOT/audits/link" 2>/dev/null \
  && [ -L "$VALIDATOR_ROOT/audits/link" ]; then
  ! bash "$VALIDATOR_ROOT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$VALIDATOR_ROOT/audits/link/audit-report-build-2026-09-26-x.md" >/dev/null 2>&1 && ok 'intermediate symlink escape fails' || bad 'intermediate symlink escape fails'
else
  pending 'intermediate symlink escape fails requires a physical symlink'
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
# Counted legs are only the ones that live in this shell; the subshell reports its own
# PENDING lines above and cannot push a number back out. PENDING is not a pass and not a
# fail, so it is stated on its own line rather than folded into the OK line.
[ "$pending_count" -eq 0 ] || echo "test-audit-integration: $pending_count PENDING leg(s) the host could not run"
echo 'test-audit-integration: OK'
