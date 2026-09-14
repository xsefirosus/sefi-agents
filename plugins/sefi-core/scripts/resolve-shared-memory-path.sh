#!/usr/bin/env bash
# resolve-shared-memory-path.sh -- print the per-OS-user shared memory-mirror root on
# stdout and exit 0, or print nothing and exit 1 when the mirror must not run this time.
# Read-only: this script never creates a directory. The caller (memory-protocol's WRITE
# step, plugins/sefi-core/scripts/ci/test-scripts.sh's callers) creates the project
# subfolder only once it actually has content to write.
#
# Fail-closed by design: any environment this script cannot positively confirm is a real,
# persistent local machine is treated as ephemeral and skipped. The project-local
# memory/ vault is the only guaranteed-durable copy; this script only ever adds a mirror
# on top of it, never in place of it.
set -uo pipefail

CONFIG="config/sefi.config.yml"

cfg_get() {
  # cfg_get <key> <default> -- read a leaf key's scalar from CONFIG. Matches
  # inject-memory.sh / gen-router.sh's own reader so config resolution stays consistent
  # across every script that reads sefi.config.yml.
  local key="$1" default="$2" val=""
  if [ -f "$CONFIG" ]; then
    val="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONFIG" | head -1)"
  fi
  printf '%s' "${val:-$default}"
}

# Honors memory.cross_project_enabled (opt out entirely) and
# memory.cross_project_folder_name (the shared folder's name) from sefi.config.yml.
ENABLED="$(cfg_get cross_project_enabled true)"
[ "$ENABLED" = "true" ] || exit 1

FOLDER_NAME="$(cfg_get cross_project_folder_name sefi-memory)"
# A blank or path-unsafe folder name is a config error; fall back to the documented
# default rather than composing a broken path.
case "$FOLDER_NAME" in ''|.|..|*/*|*\\*|*..*) FOLDER_NAME=sefi-memory ;; esac

# -- Ephemeral-environment check, FIRST and fail-closed --------------------------------
# Any one of these known markers is enough to skip. This is a known-list heuristic, not
# proof of anything -- an undetected cloud environment can still slip through, which is
# exactly why every branch below that cannot positively confirm "real local machine"
# falls through to the same exit 1, rather than defaulting to "probably fine."
is_ephemeral() {
  [ -n "${CI:-}" ] && return 0
  [ -n "${GITHUB_ACTIONS:-}" ] && return 0
  [ -n "${CODESPACES:-}" ] && return 0
  [ -n "${IS_SANDBOX:-}" ] && return 0
  [ -f /.dockerenv ] && return 0
  # systemd-detect-virt is a portable, vendor-neutral signal: any answer other than
  # "none" means this process is inside a VM or container, not on bare local hardware.
  # Live-verified: on this repo's own cloud sandbox it reports "docker" while every
  # harness-specific env var this script also checks (CI, CODESPACES, etc.) is unset --
  # without this check that exact environment resolves as "local" and writes a mirror
  # into a container that gets reclaimed on exit, silently losing it.
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt 2>/dev/null)"
    [ -n "$virt" ] && [ "$virt" != "none" ] && return 0
  fi
  return 1
}
is_ephemeral && exit 1

# -- OS branch ---------------------------------------------------------------------------
# The mirror always lives below the current user's home.  Do not guess drive roots or
# secondary mounts: those can be shared by unrelated users and make test fixtures write
# outside their isolated HOME.  We still require a known, supported local OS before
# resolving a path.
os_uname="$(uname -s 2>/dev/null || printf 'unknown')"

case "$os_uname" in
  MINGW*|MSYS*|CYGWIN*|Linux|Darwin) ;;
  *)
    # Unknown platform: cannot positively confirm anything -- fail closed rather than
    # guess a path shape for an OS this script has never been tested against.
    exit 1
    ;;
esac

[ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ] 2>/dev/null || exit 1
HOME_ROOT="$(cd "$HOME" 2>/dev/null && pwd -P)" || exit 1
printf '%s/%s\n' "${HOME_ROOT%/}" "$FOLDER_NAME"
