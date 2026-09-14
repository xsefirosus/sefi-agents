#!/usr/bin/env bash
# write-shared-memory-mirror.sh <topic-slug> <content-file> -- deterministic half of the
# cross-project memory mirror (memory-protocol/SKILL.md WRITE step 4). The privacy filter
# (WRITE step 1) already ran on <content-file> before this script is ever called -- this
# script's only job is path/slug computation and the write itself, kept mechanical rather
# than agent-freehanded, matching this repo's existing preference for a script over prose
# wherever the logic is deterministic (check-handoff.sh, check-citation.sh, and this
# script's own dependency, resolve-shared-memory-path.sh).
#
# Prints the written path on success and exits 0. On any skip or failure -- mirror
# disabled, ephemeral environment, unwritable target -- prints one line to stderr and
# exits nonzero. Never fatal to the caller: the project-local write already happened
# before this script is invoked, and is never blocked by anything here.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

TOPIC="${1:-}"
CONTENT_FILE="${2:-}"

if [ -z "$TOPIC" ] || [ -z "$CONTENT_FILE" ]; then
  echo "write-shared-memory-mirror: usage: $0 <topic-slug> <content-file>" >&2
  exit 2
fi
[ -f "$CONTENT_FILE" ] || { echo "write-shared-memory-mirror: content file not found: $CONTENT_FILE" >&2; exit 2; }

ROOT="$(bash "$HERE/resolve-shared-memory-path.sh" 2>/dev/null)" || {
  echo "write-shared-memory-mirror: skipped (mirror disabled or environment not confirmed local)" >&2
  exit 1
}
[ -n "$ROOT" ] || { echo "write-shared-memory-mirror: skipped (empty resolved path)" >&2; exit 1; }

# project-slug: sanitized `git remote get-url origin` (owner/repo form) when available, so
# two same-named repos from different remotes never collide; else the sanitized absolute
# repo path. Sanitizing means lowercase, and anything outside [a-z0-9._-] becomes a dash --
# this runs through a filesystem path, so it must never carry a "/" of its own.
sanitize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's#^https?://##; s#^git@##; s#[:/]+#-#g; s#\.git$##; s#[^a-z0-9._-]#-#g; s#-+#-#g; s#^-|-$##g'
}

is_safe_component() {
  case "$1" in
    ''|.|..|*/*|*\\*|*[!a-zA-Z0-9._-]*) return 1 ;;
  esac
  return 0
}

remote_url="$(git remote get-url origin 2>/dev/null || printf '')"
if [ -n "$remote_url" ]; then
  # HTTPS remotes may contain userinfo (including a persisted access token).  The mirror
  # path is observable output, so discard everything before the final '@' before slugging.
  case "$remote_url" in
    *://*@*) remote_url="${remote_url%%://*}://${remote_url##*@}" ;;
  esac
  project_slug="$(sanitize "$remote_url")"
else
  project_slug="$(sanitize "$(pwd)")"
fi
[ -n "$project_slug" ] || project_slug="unknown-project"
is_safe_component "$project_slug" || project_slug="unknown-project"

# harness: written by /sefi:init as the literal fact of which harness ran it. A missing or
# empty marker falls back rather than erroring -- this step is always best-effort.
harness="unknown-harness"
if [ -f .sefi/harness ]; then
  h="$(head -n1 .sefi/harness | tr -d '\r\n')"
  [ -n "$h" ] && harness="$h"
fi
is_safe_component "$harness" || {
  echo "write-shared-memory-mirror: unsafe harness marker" >&2
  exit 2
}

stamp="$(date -u +%Y-%m-%d-%H%M 2>/dev/null || printf 'unknown-time')"
topic_slug="$(sanitize "$TOPIC")"
[ -n "$topic_slug" ] || topic_slug="untitled"

project_dir="${ROOT%/}/$project_slug"
umask 077
[ ! -L "$ROOT" ] || {
  echo "write-shared-memory-mirror: unsafe mirror root" >&2
  exit 1
}
mkdir -p "$project_dir" 2>/dev/null || { echo "write-shared-memory-mirror: cannot create $project_dir" >&2; exit 1; }
[ -d "$project_dir" ] && [ ! -L "$project_dir" ] || {
  echo "write-shared-memory-mirror: unsafe project destination" >&2
  exit 1
}

# mktemp creates the file with O_EXCL, so simultaneous same-minute writes never replace
# each other or follow a preexisting destination symlink.
dest="$(mktemp "$project_dir/${harness}-${topic_slug}-${stamp}-XXXXXX.md" 2>/dev/null)" || {
  echo "write-shared-memory-mirror: cannot reserve a unique destination" >&2
  exit 1
}
[ ! -L "$dest" ] || {
  rm -f -- "$dest"
  echo "write-shared-memory-mirror: unsafe destination" >&2
  exit 1
}
cat "$CONTENT_FILE" > "$dest" 2>/dev/null || {
  rm -f -- "$dest"
  echo "write-shared-memory-mirror: cannot write $dest" >&2
  exit 1
}

printf '%s\n' "$dest"
