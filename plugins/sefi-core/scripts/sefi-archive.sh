#!/usr/bin/env bash
# sefi-archive.sh -- sourceable helper: archive before delete, never hard-delete.
#
# WHY THIS EXISTS
# install-hermes.sh grew a rollback quarantine on its own: it copies every skill
# it is about to touch into a temp root, refuses symlinked or non-directory
# targets, and restores on failure. That is the behavior we want everywhere a
# managed destructive edit replaces user-visible content -- but it existed in
# exactly one script. install-opencode.sh reached the same `rm -rf` through
# --force with no copy at all, so a mistaken --force destroyed drifted user
# edits with no way back.
#
# The rule this encodes: a managed destructive edit archives first. The archive
# is what makes the edit recoverable; the delete is just the reclaim.
#
#   . "$PLUGIN_ROOT/scripts/sefi-archive.sh"
#   sefi_archive_init "$label" || return 1        # once, before any destructive step
#   sefi_archive_put "$target" || return 1        # before rm/mv of $target
#   sefi_archive_restore                          # on failure
#   sefi_archive_purge                            # on success
#
# DESIGN NOTES (each is a deliberate choice, not an omission)
#
# * Archive root defaults under TMPDIR, not beside the target. An archive next to
#   the thing it protects is itself a managed file that install-drift checks will
#   flag, and it litters the user's harness directory.
#
# * Archive contents are copied, not moved. The caller decides when to delete.
#   That ordering is the whole point: if the copy fails, nothing is destroyed.
#
# * Restoration is fail-closed per entry and reports what it could not restore,
#   rather than continuing and claiming success.
#
# * `sefi_archive_purge` deletes the archive. That is the one hard delete here,
#   and it is guarded to refuse any path outside the archive root it created --
#   the same containment check install-hermes.sh already used for its quarantine.
#
# * Symlinks are refused, never followed. Archiving the target of a symlink would
#   copy (and later restore) content from somewhere the user never pointed the
#   installer at.

sefi_archive_init() {
  local label="${1:-sefi}"
  SEFI_ARCHIVE_LABEL="$label"
  SEFI_ARCHIVE_ROOT=""
  SEFI_ARCHIVE_ENTRIES=""
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/sefi-${label}-archive.XXXXXX")" || {
    echo "sefi-archive: cannot create archive root for '$label'" >&2
    return 1
  }
  SEFI_ARCHIVE_ROOT="$(cd -P "$root" && pwd -P)" || {
    echo "sefi-archive: cannot resolve archive root $root" >&2
    return 1
  }
  return 0
}

# sefi_archive_put <path> [--label <name>]
# Copies <path> into the archive and records it for restore. A missing path is
# recorded as absent rather than as an error: restoring "was not there" is a
# legitimate outcome and is what makes rollback exact.
sefi_archive_put() {
  local target="${1:-}" label=""
  [ -n "$target" ] || { echo "sefi-archive: sefi_archive_put needs a path" >&2; return 1; }
  if [ "${2:-}" = "--label" ]; then label="${3:-}"; fi
  [ -n "$SEFI_ARCHIVE_ROOT" ] || {
    echo "sefi-archive: sefi_archive_init was not called" >&2; return 1; }

  local resolved="" parent=""
  parent="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || {
    echo "sefi-archive: cannot resolve parent of $target" >&2; return 1; }
  resolved="$parent/$(basename "$target")"

  if [ -L "$resolved" ]; then
    echo "sefi-archive: refusing symlinked target $resolved -- archiving it would copy content from elsewhere" >&2
    return 1
  fi
  [ -e "$resolved" ] || {
    printf '%s\tmissing\n' "$resolved" >>"$SEFI_ARCHIVE_ROOT/.entries"
    return 0
  }

  local key="${label:-$(basename "$resolved")}"
  # A key collision would silently overwrite an earlier snapshot within one run.
  if [ -e "$SEFI_ARCHIVE_ROOT/$key" ] || [ -e "$SEFI_ARCHIVE_ROOT/$key.absent" ]; then
    key="$key.$(printf '%s' "$resolved" | cksum | cut -d' ' -f1)"
  fi
  cp -R "$resolved" "$SEFI_ARCHIVE_ROOT/$key" || {
    echo "sefi-archive: failed to archive $resolved -- refusing to continue, nothing was deleted" >&2
    return 1
  }
  printf '%s\t%s\n' "$resolved" "$key" >>"$SEFI_ARCHIVE_ROOT/.entries"
  return 0
}

# sefi_archive_restore -- put every archived entry back. Best effort per entry,
# but the aggregate status is a failure if anything could not be restored, and
# each failure is named.
sefi_archive_restore() {
  [ -n "$SEFI_ARCHIVE_ROOT" ] || return 0
  [ -f "$SEFI_ARCHIVE_ROOT/.entries" ] || return 0
  local restored=0 failed=0
  while IFS=$'\t' read -r dest key; do
    [ -n "$dest" ] || continue
    if [ "$key" = "missing" ]; then
      # Was not there before: remove whatever the failed step created.
      rm -rf -- "$dest"
      restored=$((restored + 1))
      continue
    fi
    local src="$SEFI_ARCHIVE_ROOT/$key"
    if [ ! -e "$src" ]; then
      echo "sefi-archive: cannot restore $dest -- archive entry $key is gone" >&2
      failed=$((failed + 1))
      continue
    fi
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    rm -rf -- "$dest"
    if cp -R "$src" "$dest"; then
      restored=$((restored + 1))
    else
      echo "sefi-archive: failed to restore $dest from $key" >&2
      failed=$((failed + 1))
    fi
  done <"$SEFI_ARCHIVE_ROOT/.entries"
  echo "sefi-archive: restore finished ($restored restored, $failed failed)" >&2
  [ "$failed" -eq 0 ]
}

# sefi_archive_purge -- discard the archive after a successful run. Refuses any
# root it did not create, so a stray variable cannot turn this into an rm -rf.
sefi_archive_purge() {
  [ -n "$SEFI_ARCHIVE_ROOT" ] || return 0
  local resolved=""
  resolved="$(cd -P "$SEFI_ARCHIVE_ROOT" 2>/dev/null && pwd -P)" || {
    echo "sefi-archive: cannot resolve archive root $SEFI_ARCHIVE_ROOT" >&2; return 1; }
  case "$resolved" in
    */sefi-"$SEFI_ARCHIVE_LABEL"-archive.*)
      rm -rf -- "$resolved"
      SEFI_ARCHIVE_ROOT=""
      return 0 ;;
    *)
      echo "sefi-archive: refusing to purge unexpected archive path $resolved" >&2
      return 1 ;;
  esac
}