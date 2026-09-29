#!/usr/bin/env bash
# install-codex.sh -- one-time Codex bootstrap for sefi-agents. Codex marketplace plugins
# cannot silently change global instructions or auto-trust executable hooks, so this script
# performs the ordinary CLI install/refresh path and owns only a marked block in AGENTS.md.
set -euo pipefail

MARKETPLACE="sefi-agents"
MARKETPLACE_SOURCE="https://github.com/xsefirosus/sefi-agents.git"
MARKETPLACE_ADD_SOURCE="xsefirosus/sefi-agents"
PLUGIN="sefi-core@sefi-agents"
START='<!-- sefi-agents:codex-bootstrap:start -->'
END='<!-- sefi-agents:codex-bootstrap:end -->'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/plugins/sefi-core"
MODEL_FOR="$CORE/scripts/model-for.sh"
MODEL_MAP=""
CANDIDATE_MARKETPLACE=""

find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import json, sys' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

print_onboarding() {
  cat <<'EOF'
sefi-agents: installation succeeded.
sefi-agents: run /sefi:init once from each project root before the first routed request.
sefi-agents: auto-init is unsafe because installation is user-wide and cannot safely choose or modify a project.
sefi-agents: cross-project memory is optional, local/private, and off by default; /sefi:init asks interactively and keeps it off when unattended.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model-map) MODEL_MAP="${2:-}"; shift 2 ;;
    --candidate-marketplace) CANDIDATE_MARKETPLACE="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: $0 [--model-map <path>] [--candidate-marketplace <repo-root>]"; exit 0 ;;
    *) echo "install-codex.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -z "$MODEL_MAP" ] || [ -f "$MODEL_MAP" ] || { echo "install-codex.sh: model map not found at $MODEL_MAP" >&2; exit 2; }

if [ -n "$CANDIDATE_MARKETPLACE" ]; then
  # Candidate installation is an explicit local verification path. It keeps the normal
  # public-source guard unchanged and requires an isolated CODEX_HOME selected by the caller.
  [ -n "${CODEX_HOME:-}" ] || { echo "install-codex.sh: --candidate-marketplace requires an explicit isolated CODEX_HOME" >&2; exit 2; }
  CANDIDATE_MARKETPLACE="$(cd "$CANDIDATE_MARKETPLACE" && pwd -P)" || {
    echo "install-codex.sh: candidate marketplace root is not readable" >&2
    exit 2
  }
  SCRIPT_ROOT="$(cd "$SCRIPT_DIR" && pwd -P)"
  [ "$CANDIDATE_MARKETPLACE" = "$SCRIPT_ROOT" ] || {
    echo "install-codex.sh: candidate marketplace must be this checkout: $SCRIPT_ROOT" >&2
    exit 2
  }
  [ -f "$CANDIDATE_MARKETPLACE/plugins/sefi-core/.codex-plugin/plugin.json" ] || {
    echo "install-codex.sh: candidate marketplace has no sefi-core Codex plugin" >&2
    exit 2
  }
  MARKETPLACE_SOURCE="$CANDIDATE_MARKETPLACE"
  MARKETPLACE_ADD_SOURCE="$CANDIDATE_MARKETPLACE"
fi

command -v codex >/dev/null 2>&1 || {
  echo "install-codex.sh: Codex CLI not found on PATH" >&2
  exit 1
}
PYTHON_BIN="$(find_python)" || {
  echo "install-codex.sh: Python is required to verify the installed plugin source and write TOML profiles" >&2
  exit 2
}

marketplace_root_from_json() {
  "$PYTHON_BIN" -c '
import json
import sys
from pathlib import Path

name, expected_source, candidate = sys.argv[1:]
def canonical(value: str) -> Path:
    return Path(value[4:] if value.startswith("\\\\?\\") else value).resolve()
try:
    document = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid Codex marketplace JSON: {exc}")
marketplaces = document.get("marketplaces")
if not isinstance(marketplaces, list):
    raise SystemExit("Codex marketplace JSON has no marketplaces list")
matches = [item for item in marketplaces if isinstance(item, dict) and item.get("name") == name]
if not matches:
    print("MISSING")
    raise SystemExit(0)
if len(matches) != 1:
    raise SystemExit(f"Codex marketplace JSON has {len(matches)} records named {name}")
record = matches[0]
root = record.get("root")
if not isinstance(root, str) or not root:
    raise SystemExit(f"configured marketplace {name} has no root")
root_path = Path(root)
if not root_path.is_dir() or root_path.is_symlink():
    raise SystemExit(f"configured marketplace {name} root is not a physical directory")
source = record.get("marketplaceSource", {}).get("source")
if candidate:
    try:
        root_matches = canonical(root) == canonical(expected_source)
    except OSError:
        root_matches = False
    if not root_matches:
        raise SystemExit(f"configured marketplace {name} root differs from the candidate")
    if source is None:
        print(root_path.resolve())
        raise SystemExit(0)
    if not isinstance(source, str) or not source:
        raise SystemExit(f"configured marketplace {name} has an invalid source")
    try:
        source_matches = canonical(source) == canonical(expected_source)
    except OSError:
        source_matches = False
else:
    if not isinstance(source, str) or not source:
        raise SystemExit(f"configured marketplace {name} has no source")
    source_matches = source == expected_source
if not source_matches:
    raise SystemExit(f"configured marketplace {name} has a different source")
print(root_path.resolve())
' "$MARKETPLACE" "$MARKETPLACE_SOURCE" "$CANDIDATE_MARKETPLACE"
}

marketplaces="$(codex plugin marketplace list --json)" || {
  echo "install-codex.sh: could not list configured Codex marketplaces" >&2
  exit 1
}
MARKETPLACE_ROOT="$(printf '%s' "$marketplaces" | marketplace_root_from_json)" || {
  echo "install-codex.sh: configured marketplace '$MARKETPLACE' failed source identity verification" >&2
  exit 1
}
if [ "$MARKETPLACE_ROOT" = "MISSING" ]; then
  codex plugin marketplace add "$MARKETPLACE_ADD_SOURCE"
  marketplaces="$(codex plugin marketplace list --json)" || {
    echo "install-codex.sh: could not re-read configured Codex marketplaces" >&2
    exit 1
  }
  MARKETPLACE_ROOT="$(printf '%s' "$marketplaces" | marketplace_root_from_json)" || {
    echo "install-codex.sh: newly added marketplace '$MARKETPLACE' failed source identity verification" >&2
    exit 1
  }
  [ "$MARKETPLACE_ROOT" != "MISSING" ] || {
    echo "install-codex.sh: marketplace '$MARKETPLACE' was not registered" >&2
    exit 1
  }
fi

if [ -z "$CANDIDATE_MARKETPLACE" ]; then
  codex plugin marketplace upgrade "$MARKETPLACE"
  marketplaces="$(codex plugin marketplace list --json)" || {
    echo "install-codex.sh: could not re-read upgraded Codex marketplace" >&2
    exit 1
  }
  MARKETPLACE_ROOT="$(printf '%s' "$marketplaces" | marketplace_root_from_json)" || {
    echo "install-codex.sh: upgraded marketplace '$MARKETPLACE' failed source identity verification" >&2
    exit 1
  }
fi

codex plugin add "$PLUGIN"

installed_plugins="$(codex plugin list --json)" || {
  echo "install-codex.sh: could not list installed Codex plugins" >&2
  exit 1
}
PROFILE_CORE="$(printf '%s' "$installed_plugins" | "$PYTHON_BIN" -c '
import hashlib
import json
import sys
from pathlib import Path

plugin, marketplace, expected_source, marketplace_root, candidate = sys.argv[1:]
def canonical(value: str) -> Path:
    return Path(value[4:] if value.startswith("\\\\?\\") else value).resolve()
try:
    document = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid Codex plugin list JSON: {exc}")
installed = document.get("installed")
if not isinstance(installed, list):
    raise SystemExit("Codex plugin list JSON has no installed list")
matches = [item for item in installed if isinstance(item, dict) and item.get("pluginId") == plugin]
if len(matches) != 1:
    raise SystemExit(f"Codex plugin list has {len(matches)} records for {plugin}")
record = matches[0]
if record.get("marketplaceName") != marketplace:
    raise SystemExit(f"installed plugin {plugin} is not bound to marketplace {marketplace}")
reported_source = record.get("marketplaceSource", {}).get("source")
if not isinstance(reported_source, str) or not reported_source:
    raise SystemExit(f"installed plugin {plugin} has no marketplace source")
if candidate:
    try:
        source_matches = canonical(reported_source) == canonical(expected_source)
    except OSError:
        source_matches = False
else:
    source_matches = reported_source == expected_source
if not source_matches:
    raise SystemExit(f"installed plugin {plugin} marketplace source differs from {marketplace}")
source = record.get("source", {}).get("path")
if not isinstance(source, str) or not source:
    raise SystemExit(f"installed plugin {plugin} has no local source path")
source_path = Path(source[4:] if source.startswith("\\\\?\\") else source)
if not source_path.is_dir() or source_path.is_symlink():
    raise SystemExit(f"installed plugin {plugin} source is not a physical directory")
source_path = source_path.resolve()
manifest = source_path / ".codex-plugin" / "plugin.json"
try:
    manifest_data = json.loads(manifest.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"installed plugin {plugin} has an unreadable manifest: {exc}")
if manifest_data.get("name") != "sefi-core":
    raise SystemExit(f"installed plugin {plugin} manifest identity differs")
if candidate:
    expected_path = (canonical(candidate) / "plugins" / "sefi-core").resolve()
    if source_path != expected_path:
        raise SystemExit(f"candidate plugin source is outside the selected checkout: {source_path}")
    def files(root: Path) -> dict[str, str]:
        result: dict[str, str] = {}
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                raise SystemExit(f"candidate plugin contains symlinked content: {path}")
            if path.is_file():
                result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        return result
    if files(source_path) != files(expected_path):
        raise SystemExit("candidate plugin source content differs from the selected checkout")
else:
    marketplace_path = Path(marketplace_root)
    if not marketplace_path.is_dir() or marketplace_path.is_symlink():
        raise SystemExit(f"marketplace {marketplace} root is not a physical directory")
    expected_path = (marketplace_path.resolve() / "plugins" / "sefi-core")
    if source_path != expected_path:
        raise SystemExit(f"installed plugin {plugin} source is outside marketplace {marketplace}")
print(source_path)
' "$PLUGIN" "$MARKETPLACE" "$MARKETPLACE_SOURCE" "$MARKETPLACE_ROOT" "$CANDIDATE_MARKETPLACE"
)" || {
  echo "install-codex.sh: cannot verify the installed source identity for $PLUGIN" >&2
  exit 1
}
if command -v cygpath >/dev/null 2>&1; then
  PROFILE_CORE="$(cygpath -u "$PROFILE_CORE")"
fi
MODEL_FOR="$PROFILE_CORE/scripts/model-for.sh"
[ -d "$PROFILE_CORE/agents" ] && [ -f "$MODEL_FOR" ] || {
  echo "install-codex.sh: installed Sefi agent sources or model resolver are missing" >&2
  exit 1
}

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
AGENTS_FILE="$CODEX_ROOT/AGENTS.md"
mkdir -p "$CODEX_ROOT"

# Codex installs the plugin sources but does not materialize plugin agent files into the
# custom-agent directory. Generate missing Sefi profiles from the installed plugin bytes
# before touching AGENTS.md, so a partial installation has no global routing side effect.
CODEX_AGENTS_DIR="$CODEX_ROOT/agents"
mkdir -p "$CODEX_AGENTS_DIR"
[ -d "$CODEX_AGENTS_DIR" ] && [ ! -L "$CODEX_AGENTS_DIR" ] || {
  echo "install-codex.sh: refusing symlinked or non-directory agents root $CODEX_AGENTS_DIR" >&2
  exit 1
}

create_missing_profile() {
  local source_agent="$1" agent_name="$2" agent_profile="$3" description=""
  "$PYTHON_BIN" - "$source_agent" "$agent_name" "$agent_profile" <<'PY'
import json
import re
import sys
from pathlib import Path

source, name, profile = map(Path, sys.argv[1:])
text = source.read_text(encoding="utf-8")
parts = re.split(r"^---\s*$", text, maxsplit=2, flags=re.MULTILINE)
if len(parts) != 3:
    raise SystemExit(f"agent source has invalid front matter: {source}")
description = next((line.partition(":")[2].strip() for line in parts[1].splitlines()
                    if line.startswith("description:")), "")
if not description:
    raise SystemExit(f"agent source has no description: {source}")
body = parts[2].lstrip("\r\n")
profile.write_text(
    f"name = {json.dumps(name.name)}\n"
    f"description = {json.dumps(description)}\n"
    f"developer_instructions = {json.dumps(body)}\n",
    encoding="utf-8",
    newline="\n",
)
PY
}

for source_agent in "$PROFILE_CORE"/agents/*.md; do
  [ -e "$source_agent" ] || continue
  agent_name="$(sed -n 's/^name:[[:space:]]*\([a-z0-9-]*\).*/\1/p' "$source_agent" | head -1)"
  [ -n "$agent_name" ] || {
    echo "install-codex.sh: cannot read Sefi agent name from $source_agent" >&2
    exit 1
  }
  agent_profile="$CODEX_AGENTS_DIR/$agent_name.toml"
  [ ! -L "$agent_profile" ] || {
    echo "install-codex.sh: refusing symlinked agent profile $agent_profile" >&2
    exit 1
  }
  [ -f "$agent_profile" ] || create_missing_profile "$source_agent" "$agent_name" "$agent_profile"
done

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
for source_agent in "$PROFILE_CORE"/agents/*.md; do
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
print_onboarding
