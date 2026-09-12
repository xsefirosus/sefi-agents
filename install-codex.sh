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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/plugins/sefi-core"
MODEL_FOR="$CORE/scripts/model-for.sh"
MODEL_MAP=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model-map) MODEL_MAP="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: $0 [--model-map <path>]"; exit 0 ;;
    *) echo "install-codex.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -z "$MODEL_MAP" ] || [ -f "$MODEL_MAP" ] || { echo "install-codex.sh: model map not found at $MODEL_MAP" >&2; exit 2; }

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

[ -d "$CORE/agents" ] && [ -f "$MODEL_FOR" ] || {
  echo "install-codex.sh: bundled Sefi agent sources or model resolver are missing" >&2
  exit 1
}

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
AGENTS_FILE="$CODEX_ROOT/AGENTS.md"
mkdir -p "$CODEX_ROOT"

# Codex creates the Sefi custom-agent profiles when the marketplace plugin is installed.
# Preflight them before touching AGENTS.md, so a partial plugin installation never leaves a
# user believing its global routing also has the requested model policy.
CODEX_AGENTS_DIR="$CODEX_ROOT/agents"
missing_profiles=""
for source_agent in "$CORE"/agents/*.md; do
  [ -e "$source_agent" ] || continue
  agent_name="$(sed -n 's/^name:[[:space:]]*\([a-z0-9-]*\).*/\1/p' "$source_agent" | head -1)"
  [ -n "$agent_name" ] || {
    echo "install-codex.sh: cannot read Sefi agent name from $source_agent" >&2
    exit 1
  }
  if [ ! -f "$CODEX_AGENTS_DIR/$agent_name.toml" ]; then
    missing_profiles="${missing_profiles}${missing_profiles:+, }$agent_name"
  fi
done

[ -z "$missing_profiles" ] || {
  echo "install-codex.sh: Codex did not create expected Sefi custom-agent profiles: $missing_profiles" >&2
  echo "install-codex.sh: global routing and model policy were left unchanged" >&2
  exit 1
}

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

# Codex custom agents are global TOML files. The plugin installs their role instructions;
# this bootstrap supplies the approved, per-specialist model policy without changing the
# user's global default model or any non-Sefi agent. Re-running replaces only these two
# fields for Sefi's own named profiles.
for source_agent in "$CORE"/agents/*.md; do
  agent_name="$(sed -n 's/^name:[[:space:]]*\([a-z0-9-]*\).*/\1/p' "$source_agent" | head -1)"
  resolver_args=()
  [ -n "$MODEL_MAP" ] && resolver_args+=(--map "$MODEL_MAP")
  agent_model="$(bash "$MODEL_FOR" --agent "$source_agent" codex "${resolver_args[@]}")" || exit 1
  agent_effort="$(bash "$MODEL_FOR" --agent "$source_agent" codex --reasoning "${resolver_args[@]}")" || exit 1
  agent_profile="$CODEX_AGENTS_DIR/$agent_name.toml"
  agent_tmp="$(mktemp "$CODEX_AGENTS_DIR/.sefi-agent.XXXXXX")"
  awk -v model="$agent_model" -v effort="$agent_effort" '
    /^model[[:space:]]*=/ { next }
    /^model_reasoning_effort[[:space:]]*=/ { next }
    /^developer_instructions[[:space:]]*=/ && !inserted {
      print "model = \"" model "\""
      print "model_reasoning_effort = \"" effort "\""
      inserted = 1
    }
    { print }
    END { if (!inserted) exit 1 }
  ' "$agent_profile" > "$agent_tmp" || {
    rm -f "$agent_tmp"
    echo "install-codex.sh: cannot apply the model policy to $agent_profile" >&2
    exit 1
  }
  mv "$agent_tmp" "$agent_profile"
done

echo "install-codex.sh: installed $PLUGIN and updated $AGENTS_FILE"
echo "install-codex.sh: applied the approved Sefi specialist model policy in $CODEX_AGENTS_DIR"
echo "install-codex.sh: start a new Codex session and accept its one-time Sefi hook trust prompt when shown."
