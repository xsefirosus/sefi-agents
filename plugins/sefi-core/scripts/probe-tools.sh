#!/usr/bin/env bash
# probe-tools.sh [--deep] [--quiet] <tool>...
# probe-tools.sh [--deep] [--quiet] --loop <path/to/x.loop.md>
#
# Probe the external commands a loop's moves depend on, BEFORE the loop runs. A loop that
# assumes a tool it does not have degrades to a silent no-op and burns a whole cycle
# discovering it: this repo's own first live triage (state/triage.md, 2026-07-16) filed two
# of six findings as "gh CLI not installed ... unreachable this cycle", and a predecessor
# system let a broken browser tool eat a 50-iteration retry budget.
#
# Presence is not health. `command -v` passes for a binary that is installed and broken --
# which is exactly what the browser-tool failure was -- so each tool gets a smoke command
# as well. This consolidates the ad-hoc `command -v` checks that were already scattered
# across budget-check.sh and gate.sh.
#
# Offline by default: the smoke command is a local `--version`-style call, never a network
# request, because the plugin makes no network calls. --deep opts in to checks that may
# touch a network or a credential store (e.g. `gh auth status`), and is never implied.
#
# States, and why there are four rather than two:
#   OK          on PATH and its smoke command succeeded
#   UNVERIFIED  on PATH but cannot self-report; presence is all that is known
#   BROKEN      on PATH and its smoke command FAILED -- installed but unusable
#   MISSING     not on PATH
# Exit 0 when every tool is OK or UNVERIFIED; exit 1 if any is BROKEN or MISSING. Claiming
# UNVERIFIED as OK would rebuild the overclaim this script exists to remove.
set -uo pipefail

DEEP=0
QUIET=0
LOOP_FILE=""
TOOLS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --deep)  DEEP=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --loop)  LOOP_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    -*) echo "probe-tools: unknown arg $1" >&2; exit 2 ;;
    *) TOOLS+=("$1"); shift ;;
  esac
done

if [ -n "$LOOP_FILE" ]; then
  [ -f "$LOOP_FILE" ] || { echo "probe-tools: $LOOP_FILE not found" >&2; exit 2; }
  # `requires-tools: git, gh, rg` -- the loop spec's declaration of what its moves need.
  line="$(sed -n 's/^requires-tools:[[:space:]]*//p' "$LOOP_FILE" | head -1)"
  if [ -z "$line" ]; then
    echo "probe-tools: $LOOP_FILE declares no 'requires-tools:' line; nothing to probe" >&2
    exit 2
  fi
  # `requires-tools: none` is a deliberate declaration of no external dependency, not an
  # empty value to fall through on.
  case "$(printf '%s' "$line" | tr -d '[:space:]')" in
    none|None|NONE)
      report_none="probe-tools: $LOOP_FILE declares no external tool dependencies (requires-tools: none)"
      [ "${QUIET:-0}" -eq 1 ] || printf '%s\n' "$report_none"
      exit 0 ;;
  esac
  old_ifs="$IFS"; IFS=','
  for t in $line; do
    t="$(printf '%s' "$t" | tr -d '[:space:]')"
    [ -n "$t" ] && TOOLS+=("$t")
  done
  IFS="$old_ifs"
fi

[ "${#TOOLS[@]}" -gt 0 ] || { echo "probe-tools: no tools given (pass tool names or --loop <file>)" >&2; exit 2; }

smoke_for() {
  # smoke_for <tool> -- the offline liveness command for a known tool, else empty.
  case "$1" in
    gh|jq|rg|git|node|npm|pnpm|yarn|bun|go|cargo|python3|pip3|ruff|pytest|shellcheck|timeout|ccusage|docker|opencode|codex|claude)
      printf '%s --version' "$1" ;;
    *) printf '' ;;
  esac
}

deep_for() {
  # deep_for <tool> -- an authorization/connectivity check. Only run under --deep: these
  # may contact a network or read a credential store.
  case "$1" in
    gh)     printf 'gh auth status' ;;
    git)    printf 'git rev-parse --git-dir' ;;
    docker) printf 'docker info' ;;
    *) printf '' ;;
  esac
}

failures=0
report() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$1"; }

for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    report "MISSING    $tool -- not on PATH"
    failures=$((failures + 1))
    continue
  fi

  smoke="$(smoke_for "$tool")"
  if [ -z "$smoke" ]; then
    # Unknown tool: try --version as a best effort, but never upgrade a silent success
    # into an OK claim we did not actually verify.
    if $tool --version >/dev/null 2>&1; then
      report "OK         $tool -- responds to --version"
    else
      report "UNVERIFIED $tool -- on PATH, no known health check (presence only)"
    fi
    continue
  fi

  if $smoke >/dev/null 2>&1; then
    if [ "$DEEP" -eq 1 ]; then
      deep="$(deep_for "$tool")"
      if [ -n "$deep" ]; then
        if $deep >/dev/null 2>&1; then
          report "OK         $tool -- live ($deep)"
        else
          report "BROKEN     $tool -- installed but '$deep' failed (unauthenticated or unreachable)"
          failures=$((failures + 1))
        fi
        continue
      fi
    fi
    report "OK         $tool"
  else
    report "BROKEN     $tool -- on PATH but '$smoke' failed"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  report "probe-tools: $failures tool(s) unusable -- a loop must degrade to stated reduced scope, not proceed as if they worked"
  exit 1
fi
report "probe-tools: all ${#TOOLS[@]} tool(s) usable"
exit 0
