#!/usr/bin/env bash
# sefi-recovery-point.sh -- sourceable helper: a named, restorable point in a
# destructive run, distinct from the human PR boundary.
#
# NAMING (deliberate, and load-bearing)
# "Checkpoint" already means something specific in this repo: the human
# checkpoint, the permanent PR boundary that never gets optimized away
# (skills/sefi-orchestration/references/human-checkpoint.md, docs/CHECKLIST.md).
# A second thing called a checkpoint would collide with that in prose and in
# anyone's reading of a log line, so this one is named sefi-recovery-point.
#
# HOW IT DIFFERS FROM sefi-archive.sh
# The archive helper is anonymous and run-scoped: init, put, restore, purge, all
# within one process, and the archive dies with the run. A recovery point is the
# opposite on both axes:
#
#   * it is NAMED and persists across processes, so a failure found minutes or
#     days later -- by a human, by the next scheduled run, by CI -- can still be
#     rolled back. That is the whole point: the archive cannot help you if the
#     process that made it is gone.
#   * it is INSPECTED and explicitly discarded, never auto-purged. A mechanism
#     that deletes its own undo history on success has an undo history with a
#     very short life.
#
# So: use sefi-archive.sh for "roll back this run if it fails". Use a recovery
# point for "keep the ability to roll this back until someone decides otherwise".
#
# USAGE
#   . "$PLUGIN_ROOT/scripts/sefi-recovery-point.sh"
#   rp_create "<label>"                        # start a point (id auto-stamped)
#   rp_protect "<path>"                        # snapshot a path into the point
#   rp_list                                    # show points, newest last
#   rp_restore "<id>"                          # put a point's contents back
#   rp_discard "<id>"                          # deliberately drop a point
#
# SAFETY RULES, each of which exists because the alternative is unrecoverable
#   * Points live under one root. Nothing is written outside it, and rp_discard
#     refuses any id that does not resolve inside it.
#   * rp_protect refuses symlinks, for the same reason the archive helper does:
#     snapshotting through a link copies content from elsewhere.
#   * rp_restore never deletes. It writes what the point holds and reports what
#     it could not place; it does not clear the destination first, because
#     overwriting a partial restore is worse than leaving a conflict visible.
#   * A point's contents are read-only in practice: restore copies out of them,
#     and nothing in this helper writes into a point after rp_protect.

SEFI_RP_ROOT="${SEFI_RP_ROOT:-${TMPDIR:-/tmp}/sefi-recovery-points}"

_rp_now() { date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf 'unknown-time\n'; }

_rp_resolve_root() {
  mkdir -p "$SEFI_RP_ROOT" 2>/dev/null || {
    echo "sefi-recovery-point: cannot create root $SEFI_RP_ROOT" >&2
    return 1
  }
  (cd -P "$SEFI_RP_ROOT" && pwd -P) || {
    echo "sefi-recovery-point: cannot resolve root $SEFI_RP_ROOT" >&2
    return 1
  }
}

# rp_create <label> -> echoes the new point ID (the bare id, not the full path:
# every other function here takes the id, and returning the path made a
# create-then-restore round trip fail with "no such point").
rp_create() {
  local label="${1:-point}" root id
  root="$(_rp_resolve_root)" || return 1
  # Ids are label + UTC stamp. The label is sanitized to a filesystem-safe form
  # rather than rejected: a caller should not have to invent a name that happens
  # to be shell-safe, and the id still needs to be greppable in a log.
  label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-' 2>/dev/null)"
  label="${label#-}"; label="${label%-}"
  [ -n "$label" ] || label="point"
  id="$label-$(_rp_now)"
  # Two points in the same second would collide; disambiguate rather than
  # silently overwriting the first, which is exactly the failure an undo history
  # must not have.
  local n=1
  while [ -e "$root/$id" ]; do
    id="$label-$(_rp_now)-$n"
    n=$((n + 1))
  done
  mkdir -p "$root/$id/paths" || {
    echo "sefi-recovery-point: cannot create point $id" >&2; return 1
  }
  : >"$root/$id/manifest"
  printf '%s\n' "$id"
}

# rp_protect <path> [point-id] -- snapshot one path into the point.
# Defaults to the most recently created point.
rp_protect() {
  local target="${1:-}" root id resolved parent key
  [ -n "$target" ] || { echo "sefi-recovery-point: rp_protect needs a path" >&2; return 1; }
  root="$(_rp_resolve_root)" || return 1
  id="${2:-}"
  if [ -z "$id" ]; then
    id="$(ls -1t "$root" 2>/dev/null | head -1)"
    [ -n "$id" ] || { echo "sefi-recovery-point: no point to protect into (call rp_create first)" >&2; return 1; }
  fi
  [ -d "$root/$id" ] || { echo "sefi-recovery-point: no such point '$id'" >&2; return 1; }

  parent="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || {
    echo "sefi-recovery-point: cannot resolve parent of $target -- nothing was copied" >&2
    return 1; }
  resolved="$parent/$(basename "$target")"

  if [ -L "$resolved" ]; then
    echo "sefi-recovery-point: refusing symlinked target $resolved -- snapshotting it would copy content from elsewhere" >&2
    return 1
  fi
  if [ ! -e "$resolved" ]; then
    printf '%s\tmissing\n' "$resolved" >>"$root/$id/manifest"
    return 0
  fi

  key="$(printf '%s' "$resolved" | tr '/' '_')"
  if [ -e "$root/$id/paths/$key" ]; then
    key="$key.$(printf '%s' "$resolved" | cksum | cut -d' ' -f1)"
  fi
  cp -R "$resolved" "$root/$id/paths/$key" || {
    echo "sefi-recovery-point: failed to snapshot $resolved" >&2
    return 1
  }
  printf '%s\t%s\n' "$resolved" "$key" >>"$root/$id/manifest"
}

# rp_list -- one line per point, oldest first, with what it holds.
rp_list() {
  local root
  root="$(_rp_resolve_root)" || return 1
  local found=0 p
  for p in "$root"/*; do
    [ -d "$p" ] || continue
    found=1
    printf '%s\t%s path(s)\n' "$(basename "$p")" "$(grep -c . "$p/manifest" 2>/dev/null || echo 0)"
  done
  [ "$found" -eq 1 ] || echo "(no recovery points)"
}

# rp_restore <id> -- copy a point's contents back. Never deletes.
rp_restore() {
  local id="${1:-}" root
  [ -n "$id" ] || { echo "sefi-recovery-point: rp_restore needs a point id" >&2; return 1; }
  root="$(_rp_resolve_root)" || return 1
  [ -d "$root/$id" ] || { echo "sefi-recovery-point: no such point '$id'" >&2; return 1; }
  [ -f "$root/$id/manifest" ] || { echo "sefi-recovery-point: point '$id' has no manifest" >&2; return 1; }

  local restored=0 failed=0 dest key src
  while IFS=$'\t' read -r dest key; do
    [ -n "$dest" ] || continue
    if [ "$key" = "missing" ]; then
      # Was not there when the point was taken. Say so rather than guessing:
      # creating or removing a path is a decision, not a restore.
      echo "sefi-recovery-point: $dest did not exist at this point; left as-is" >&2
      continue
    fi
    src="$root/$id/paths/$key"
    if [ ! -e "$src" ]; then
      echo "sefi-recovery-point: cannot restore $dest -- snapshot $key is missing" >&2
      failed=$((failed + 1))
      continue
    fi
    if [ -e "$dest" ]; then
      # Present and different: restoring over it would destroy whatever is
      # there now. Name it and leave it.
      if cmp -s "$src" "$dest" 2>/dev/null || diff -rq "$src" "$dest" >/dev/null 2>&1; then
        restored=$((restored + 1))
        continue
      fi
      echo "sefi-recovery-point: $dest exists and differs; left untouched (copy from $root/$id/paths/$key by hand)" >&2
      failed=$((failed + 1))
      continue
    fi
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    if cp -R "$src" "$dest"; then
      restored=$((restored + 1))
    else
      echo "sefi-recovery-point: failed to restore $dest" >&2
      failed=$((failed + 1))
    fi
  done <"$root/$id/manifest"
  echo "sefi-recovery-point: restore of '$id' finished ($restored restored, $failed need attention)" >&2
  [ "$failed" -eq 0 ]
}

# rp_discard <id> -- deliberately drop a point. Never automatic.
rp_discard() {
  local id="${1:-}" root resolved
  [ -n "$id" ] || { echo "sefi-recovery-point: rp_discard needs a point id" >&2; return 1; }
  root="$(_rp_resolve_root)" || return 1
  case "$id" in */*|.|..)
    echo "sefi-recovery-point: refusing to discard an id containing a path separator: $id" >&2
    return 1 ;;
  esac
  resolved="$(cd -P "$root/$id" 2>/dev/null && pwd -P)" || {
    echo "sefi-recovery-point: no such point '$id'" >&2; return 1; }
  case "$resolved" in
    "$root"/*) rm -rf -- "$resolved"; return 0 ;;
    *) echo "sefi-recovery-point: refusing to discard outside the points root: $resolved" >&2; return 1 ;;
  esac
}