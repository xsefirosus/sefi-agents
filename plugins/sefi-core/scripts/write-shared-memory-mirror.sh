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

remote_url="$(git remote get-url origin 2>/dev/null || printf '')"
if [ -n "$remote_url" ]; then
  project_slug="$(sanitize "$remote_url")"
else
  project_slug="$(sanitize "$(pwd)")"
fi
[ -n "$project_slug" ] || project_slug="unknown-project"

# harness: written by /sefi:init as the literal fact of which harness ran it. A missing or
# empty marker falls back rather than erroring -- this step is always best-effort.
harness="unknown-harness"
if [ -f .sefi/harness ]; then
  h="$(head -n1 .sefi/harness | tr -d '[:space:]')"
  [ -n "$h" ] && harness="$h"
fi

stamp="$(date -u +%Y-%m-%d-%H%M 2>/dev/null || printf 'unknown-time')"
topic_slug="$(sanitize "$TOPIC")"
[ -n "$topic_slug" ] || topic_slug="untitled"

project_dir="${ROOT%/}/$project_slug"
mkdir -p "$project_dir" 2>/dev/null || { echo "write-shared-memory-mirror: cannot create $project_dir" >&2; exit 1; }

dest="$project_dir/${harness}-${topic_slug}-${stamp}.md"
cp "$CONTENT_FILE" "$dest" 2>/dev/null || { echo "write-shared-memory-mirror: cannot write $dest" >&2; exit 1; }

printf '%s\n' "$dest"
