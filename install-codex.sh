#!/usr/bin/env bash
# install-codex.sh -- one-time Codex bootstrap for sefi-agents. Codex marketplace plugins
# cannot silently change global instructions or auto-trust executable hooks, so this script
# performs the ordinary CLI install/refresh path and owns only a marked block in AGENTS.md.
set -euo pipefail

MARKETPLACE="sefi-agents"
MARKETPLACE_SOURCE="https://github.com/xsefirosus/sefi-agents.git"
PLUGIN="sefi-core@sefi-agents"
START='<!-- sefi-agents:codex-bootstrap:start -->'
END='<!-- sefi-agents:codex-bootstrap:end -->'

command -v codex >/dev/null 2>&1 || {
  echo "install-codex.sh: Codex CLI not found on PATH" >&2
  exit 1
}

marketplaces="$(codex plugin marketplace list --json)" || {
  echo "install-codex.sh: could not list configured Codex marketplaces" >&2
  exit 1
}

if printf '%s\n' "$marketplaces" | grep -q '"name"[[:space:]]*:[[:space:]]*"sefi-agents"'; then
  if ! printf '%s\n' "$marketplaces" | grep -qF "$MARKETPLACE_SOURCE"; then
    echo "install-codex.sh: configured marketplace 'sefi-agents' has a different source; refusing to replace it" >&2
    exit 1
  fi
else
  codex plugin marketplace add xsefirosus/sefi-agents
fi

codex plugin marketplace upgrade "$MARKETPLACE"
codex plugin add "$PLUGIN"

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
AGENTS_FILE="$CODEX_ROOT/AGENTS.md"
mkdir -p "$CODEX_ROOT"

block_file="$(mktemp "$CODEX_ROOT/.sefi-agents-block.XXXXXX")"
clean_file="$(mktemp "$CODEX_ROOT/.sefi-agents-clean.XXXXXX")"
output_file="$(mktemp "$CODEX_ROOT/.sefi-agents-output.XXXXXX")"
cleanup() { rm -f "$block_file" "$clean_file" "$output_file"; }
trap cleanup EXIT

cat > "$block_file" <<'BLOCK'
<!-- sefi-agents:codex-bootstrap:start -->
# Sefi orchestration

For every user request in every project, invoke `sefi-core:sefi-orchestration` before
acting. Follow its Stage 0 and routing table, use the required skills and budgets, and
dispatch the specialists its route requires. A genuinely trivial request may use that
skill's documented exception and avoid unnecessary dispatch. Explicit user instructions
override this block.
<!-- sefi-agents:codex-bootstrap:end -->
BLOCK

if [ -f "$AGENTS_FILE" ]; then
  awk -v start="$START" -v end="$END" '
    {
      raw = $0
      line = raw
      sub(/\r$/, "", line)
      if (line == start) {
        if (inside || seen_start) exit 2
        inside = 1
        seen_start = 1
        next
      }
      if (line == end) {
        if (!inside) exit 3
        inside = 0
        seen_end = 1
        next
      }
      if (!inside) print raw
    }
    END {
      if (inside || (seen_start && !seen_end) || (!seen_start && seen_end)) exit 4
    }
  ' "$AGENTS_FILE" > "$clean_file" || {
    echo "install-codex.sh: malformed or duplicate Sefi block in $AGENTS_FILE; left unchanged" >&2
    exit 1
  }
else
  : > "$clean_file"
fi

cat "$clean_file" > "$output_file"
if [ -s "$output_file" ] && [ "$(tail -c 1 "$output_file" 2>/dev/null || true)" != "" ]; then
  printf '\n' >> "$output_file"
fi
cat "$block_file" >> "$output_file"
mv "$output_file" "$AGENTS_FILE"

echo "install-codex.sh: installed $PLUGIN and updated $AGENTS_FILE"
echo "install-codex.sh: start a new Codex session and accept its one-time Sefi hook trust prompt when shown."
