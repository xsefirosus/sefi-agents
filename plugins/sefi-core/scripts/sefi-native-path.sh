#!/usr/bin/env bash
# sefi-native-path.sh -- sourceable helper: convert an MSYS path for native tools.
#
# WHY THIS EXISTS (live-confirmed 2026-10-03, Windows/git-bash)
# bash under MSYS reports paths as /c/Users/<user>/... Native Windows programs
# read that as \c\Users\<user>\... and fail. Two distinct casualties showed up
# in CI:
#
#   * native Python  -> FileNotFoundError on every path (see sefi-python.sh)
#   * native git     -> "fatal: cannot change to '/c/...'". A fixture that
#                       inits a repo through `git -C` therefore never creates a
#                       commit, so every downstream version field correctly
#                       reads UNKNOWN -- which reads like a manifest bug and is
#                       actually a path bug.
#
# sefi_native_path echoes the argument unchanged on POSIX hosts and its
# cygpath -m equivalent on MSYS hosts:
#
#   . "$(dirname "$0")/sefi-native-path.sh"
#   git -C "$(sefi_native_path "$TMP")" init -q
#
# It is deliberately separate from sefi_python_bin: git needs a translated path
# passed as an ARGUMENT, while Python needs a WRAPPER that rewrites arguments
# from inside.
sefi_native_path() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    printf '%s\n' ""
    return 0
  fi
  if command -v cygpath >/dev/null 2>&1; then
    local converted
    converted="$(cygpath -m "$path" 2>/dev/null)" || converted=""
    if [ -n "$converted" ]; then
      printf '%s\n' "$converted"
      return 0
    fi
  fi
  printf '%s\n' "$path"
}
