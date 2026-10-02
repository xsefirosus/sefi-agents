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

sefi_normalize_path() {
  # sefi_normalize_path <path> -- absolutize <path> and lexically collapse
  # duplicate slashes, dot components, and dot-dot components (clamped at the
  # root), stripping trailing slashes, so a spelled path can be compared byte
  # for byte against its physical location below. Returns non-zero and prints
  # nothing for input no POSIX layer can interpret: a backslash anywhere, or a
  # drive-letter prefix.
  #
  # That refusal is deliberate fail-closed portability, not an oversight. Every
  # installer already runs a Windows-style path through cygpath -u at its entry
  # point, so a backslash or drive letter that survives to here is input nothing
  # normalized. Read as a path it is ONE legal relative component -- "C:\Users\you"
  # is a valid directory name -- and mkdir -p would create it under $PWD rather
  # than installing anywhere the caller named. Refusing costs a caller who typed
  # the wrong form one clear message; guessing costs them a silent install in a
  # directory they never asked for.
  #
  # sefi: this helper and sefi_canonical_path are triplicated per installer
  # instead of sourced from one file, because install.sh and install-codex.sh
  # must keep working from a checkout whose plugin tree is not installed yet.
  # Ceiling: a fix applied to one copy can drift from the other two. Upgrade
  # path: the installer suite asserts the three copies are byte-identical, so
  # drift fails there; the real fix is one shared sourced helper, deferred until
  # the bootstrap can guarantee that file is present.
  local path="$1" rest="" piece="" result="" stripped=""
  case "$path" in
    # Empty input normalized to $PWD, which would hand the caller the working directory
    # as a destination nobody named. No installer can reach it today -- every entry
    # point substitutes a default for an empty variable -- so this is a pinned
    # invariant, not a reachable bug.
    "") return 1 ;;
    *\\*) return 1 ;;
    [A-Za-z]:*) return 1 ;;
    /*)
      # Strip EVERY leading slash, not just the first. "//C:/x" and "///C:/x" spell
      # the same MSYS-style drive path as "/C:/x", but a one-slash strip leaves a
      # separator in front of the drive letter, the case below matches nothing, and
      # the drive-letter path sails through to be folded in as one relative
      # component -- the exact failure this refusal exists to prevent.
      stripped="$path"
      while [ "${stripped#/}" != "$stripped" ]; do stripped="${stripped#/}"; done
      case "$stripped" in [A-Za-z]:*) return 1 ;; esac
      ;;
  esac
  case "$path" in /*) : ;; *) path="$PWD/$path" ;; esac
  rest="$path"
  while [ -n "$rest" ]; do
    piece="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$piece" in
      ""|.) continue ;;
      ..) result="${result%/*}" ;;
      *) result="$result/$piece" ;;
    esac
  done
  [ -n "$result" ] || result="/"
  printf '%s' "$result"
}

sefi_canonical_path() {
  # sefi_canonical_path <path> -- print the physical location of <path>,
  # resolving every symlink component. A non-existent leaf is handled by fully
  # canonicalizing the nearest existing ancestor with cd -P/pwd -P (not a bare
  # -L test on it) and reattaching the remainder. Fails when no physical
  # directory location can be established, or when <path> is not a POSIX path.
  #
  # The two halves of that result are spelled differently, so they are normalized
  # back together rather than concatenated raw: `pwd -P` prints the filesystem
  # root as "/", and the remainder carries its own leading separator, so a plain
  # concatenation against a root ancestor prints "//a/b". The refusal check below
  # compares this value against the spelled path byte for byte, so a doubled
  # separator is not cosmetic -- it would refuse a legitimate destination whose
  # nearest existing ancestor is the root. Reusing sefi_normalize_path keeps one
  # definition of the canonical spelling instead of a second hand-rolled slash
  # fixup that can drift from the first.
  local probe="$1" parent="" remainder="" phys=""
  probe="$(sefi_normalize_path "$probe")" || return 1
  while [ ! -e "$probe" ] && [ ! -L "$probe" ]; do
    parent="$(dirname "$probe")"
    [ "$parent" != "$probe" ] || break
    remainder="/$(basename "$probe")$remainder"
    probe="$parent"
  done
  [ -d "$probe" ] || return 1
  phys="$(cd -P "$probe" 2>/dev/null && pwd -P)" || return 1
  sefi_normalize_path "$phys$remainder"
}

sefi_inside_or_equal() {
  # sefi_inside_or_equal <candidate> <root> -- succeed when <candidate> equals
  # <root> or sits inside it. A literal prefix comparison (no glob), so parent
  # directories containing glob characters cannot confuse the test. A root of
  # "/" only ever matches itself.
  local candidate="$1" root="$2"
  [ -n "$candidate" ] && [ -n "$root" ] || return 1
  [ "$candidate" = "$root" ] && return 0
  [ "$root" = "/" ] && return 1
  [ "${candidate:0:${#root}}" = "$root" ] || return 1
  [ "${candidate:${#root}:1}" = "/" ] || return 1
  return 0
}

sefi_assert_write_target() {
  # sefi_assert_write_target <target> <root> <label> -- re-verify at the write site
  # itself that <target> still resolves inside <root>.
  #
  # The directory gate below runs once, before any write. Anyone with write access to
  # a parent directory can swap an already-verified directory for a symlink in the
  # window between that gate and the write, and every later write then lands wherever
  # the symlink points -- a directory gate alone is a check-then-act race. Re-resolving
  # the exact path being written, immediately before the write, closes the window for
  # the whole install: a directory swapped mid-run is caught by the next write site
  # instead of being followed. Callers pass the path they are about to write (not just
  # CODEX_ROOT), because the agents/ subtree is the thing that gets swapped.
  #
  # sefi: this constrains SYMLINKED DESTINATIONS only. It does not and cannot
  # constrain an arbitrary spelling a caller passed in -- a caller who names a
  # legitimate in-tree path, or one reachable only through a symlink it controls
  # above <root>, has already satisfied the gate, and this is not a sanitiser for
  # caller-supplied path text. Ceiling: a re-check still leaves a sub-millisecond
  # window between this test and the following write, because POSIX shell offers no
  # way to open a directory handle once and write relative to it. Upgrade path: this
  # installer already requires $PYTHON_BIN, so the staged writes can be moved behind
  # os.open(..., O_NOFOLLOW) so the containment decision and the write share one
  # file descriptor.
  local target_phys="" root_phys="" parent_phys=""
  # Resolve the directory that will actually receive the bytes. An existing directory
  # (including one reached through a symlink) is canonicalized directly, which is what
  # catches a swapped subtree. Anything else is resolved through its parent directory
  # and the leaf reattached, because sefi_canonical_path is defined over directories
  # and would refuse a regular file it was handed.
  if [ -d "$1" ]; then
    target_phys="$(sefi_canonical_path "$1")" || {
      echo "$3: refusing write target with no physical location: $1" >&2
      return 1
    }
  else
    parent_phys="$(sefi_canonical_path "$(dirname "$1")")" || {
      echo "$3: refusing write target with no physical parent directory: $1" >&2
      return 1
    }
    target_phys="$parent_phys/$(basename "$1")"
  fi
  root_phys="$(sefi_canonical_path "$2")" || {
    echo "$3: refusing to write because the install root has no physical location: $2" >&2
    return 1
  }
  sefi_inside_or_equal "$target_phys" "$root_phys" || {
    echo "$3: refusing write target escaping the install root: $1 resolves to $target_phys" >&2
    return 1
  }
  return 0
}

refuse_escaped_codex_root() {
  # refuse_escaped_codex_root -- refuse when CODEX_ROOT resolves outside its
  # expected location. The root is normalized (trailing slashes stripped, so a
  # trailing slash cannot blind the checks) and resolved to its physical
  # location, canonicalizing the nearest existing ancestor fully instead of
  # testing -L on it, so an existing victim/subdir reached through a symlinked
  # parent cannot slip through. The physical root must equal the spelled root
  # (no symlink hop anywhere in the chain) or sit inside the canonical HOME
  # tree; anything else is an escape and the install stops before mkdir -p
  # can follow it. Input the normalizer refuses is fatal here rather than
  # silently becoming the empty string, which would otherwise sail through the
  # comparisons below and hand mkdir -p an unverified root.
  #
  # Scope: this gate constrains SYMLINKED DESTINATIONS only, not arbitrary caller
  # spellings. A caller who passes a legitimate in-tree path (or one that resolves
  # into HOME through a symlink the user themself manages) is accepted by design; the
  # check is not a sanitiser for caller-supplied path text.
  local normalized_root=""
  normalized_root="$(sefi_normalize_path "$CODEX_ROOT")" || {
    echo "install-codex.sh: refusing CODEX_HOME that is not a POSIX path: $CODEX_ROOT" >&2
    return 1
  }
  CODEX_ROOT="$normalized_root"
  CODEX_ROOT_PHYS="$(sefi_canonical_path "$CODEX_ROOT")" || {
    echo "install-codex.sh: refusing CODEX_HOME with no physical location: $CODEX_ROOT" >&2
    return 1
  }
  CODEX_HOME_PHYS="$(sefi_canonical_path "$HOME")" || CODEX_HOME_PHYS=""
  if [ "$CODEX_ROOT_PHYS" != "$CODEX_ROOT" ] && ! sefi_inside_or_equal "$CODEX_ROOT_PHYS" "$CODEX_HOME_PHYS"; then
    echo "install-codex.sh: refusing CODEX_HOME escaping its expected root: $CODEX_ROOT resolves to $CODEX_ROOT_PHYS" >&2
    return 1
  fi
}

refuse_escaped_codex_agents() {
  # refuse_escaped_codex_agents -- refuse when the agents directory resolves
  # anywhere but the agents child of the verified CODEX_ROOT. Exact equality
  # with the expected physical path is required, so neither a symlinked agents
  # directory nor a shifted parent can redirect profile writes.
  #
  # Scope: exact physical equality constrains SYMLINKED DESTINATIONS only, not
  # arbitrary caller spellings. It answers "does this path still resolve to
  # CODEX_ROOT/agents", not "is this string a well-formed path the caller was
  # allowed to name"; the spelling was settled once, by refuse_escaped_codex_root
  # plus sefi_normalize_path, before this function is ever called.
  CODEX_AGENTS_PHYS="$(sefi_canonical_path "$CODEX_AGENTS_DIR")" || {
    echo "install-codex.sh: refusing agents dir with no physical location: $CODEX_AGENTS_DIR" >&2
    return 1
  }
  [ "$CODEX_AGENTS_PHYS" = "$CODEX_ROOT_PHYS/agents" ] || {
    echo "install-codex.sh: refusing agents dir escaping its expected root: $CODEX_AGENTS_DIR resolves to $CODEX_AGENTS_PHYS" >&2
    return 1
  }
}

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
AGENTS_FILE="$CODEX_ROOT/AGENTS.md"
refuse_escaped_codex_root || exit 1
mkdir -p "$CODEX_ROOT"
[ -d "$CODEX_ROOT" ] || {
  echo "install-codex.sh: refusing non-directory CODEX_HOME root $CODEX_ROOT" >&2
  exit 1
}
refuse_escaped_codex_root || exit 1

# Codex installs the plugin sources but does not materialize plugin agent files into the
# custom-agent directory. Generate missing Sefi profiles from the installed plugin bytes
# before touching AGENTS.md, so a partial installation has no global routing side effect.
CODEX_AGENTS_DIR="$CODEX_ROOT/agents"
refuse_escaped_codex_agents || exit 1
mkdir -p "$CODEX_AGENTS_DIR"
[ -d "$CODEX_AGENTS_DIR" ] || {
  echo "install-codex.sh: refusing non-directory agents root $CODEX_AGENTS_DIR" >&2
  exit 1
}
refuse_escaped_codex_agents || exit 1

create_missing_profile() {
  # create_missing_profile <source-agent> <agent-name> <output> -- render the
  # profile into <output>, which must be a staging file owned by this install,
  # never the live profile path itself. The caller moves the staged file into
  # place with mv -n, so a symlink swapped in at the destination cannot be
  # followed by this write.
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
  # Re-verify the agents directory at this write site, not only at the gate above.
  # refuse_escaped_codex_agents re-canonicalizes CODEX_AGENTS_DIR on every call, so a
  # agents/ directory swapped for a symlink after the gate is caught here -- before
  # the staging mktemp below creates a file inside whatever it now points at.
  refuse_escaped_codex_agents || exit 1
  sefi_assert_write_target "$agent_profile" "$CODEX_ROOT_PHYS/agents" \
    "install-codex.sh: refusing to write $agent_profile" || exit 1
  [ ! -L "$agent_profile" ] || {
    echo "install-codex.sh: refusing symlinked agent profile $agent_profile" >&2
    exit 1
  }
  if [ ! -e "$agent_profile" ]; then
    # Render into a staging file owned by this install and move it into place,
    # so a symlink swapped in after the check above cannot divert the new
    # profile bytes into another file. mv replaces (never follows) whatever
    # sits at the destination; the re-check keeps a raced-in entry from being
    # silently replaced instead (the second pass re-checks before writing).
    agent_new_tmp="$(mktemp "$CODEX_AGENTS_DIR/.sefi-agent-new.XXXXXX")" || exit 1
    # Re-verify immediately after staging too: mktemp is the first filesystem call at
    # this write site, so a directory swapped during it must be caught before the
    # profile bytes are rendered into the staging file.
    refuse_escaped_codex_agents || { rm -f "$agent_new_tmp"; exit 1; }
    sefi_assert_write_target "$agent_new_tmp" "$CODEX_ROOT_PHYS/agents" \
      "install-codex.sh: refusing to stage $agent_profile" || { rm -f "$agent_new_tmp"; exit 1; }
    create_missing_profile "$source_agent" "$agent_name" "$agent_new_tmp"
    if [ -e "$agent_profile" ] || [ -L "$agent_profile" ]; then
      rm -f "$agent_new_tmp"
    else
      mv -n "$agent_new_tmp" "$agent_profile" || {
        rm -f "$agent_new_tmp"
        echo "install-codex.sh: cannot stage new agent profile $agent_profile" >&2
        exit 1
      }
      rm -f "$agent_new_tmp"
    fi
  fi
  # Re-verify after the render, immediately before the mv: create_missing_profile runs
  # an interpreter over the source file, which is the widest window in this loop for a
  # directory swap, and the mv would otherwise carry the staged bytes straight through.
  refuse_escaped_codex_agents || exit 1
  sefi_assert_write_target "$agent_profile" "$CODEX_ROOT_PHYS/agents" \
    "install-codex.sh: refusing to write $agent_profile" || exit 1
done

refuse_escaped_codex_root || exit 1
sefi_assert_write_target "$CODEX_ROOT" "$CODEX_ROOT_PHYS" \
  "install-codex.sh: refusing to stage bootstrap files in $CODEX_ROOT" || exit 1
block_file="$(mktemp "$CODEX_ROOT/.sefi-agents-block.XXXXXX")" || exit 1
clean_file="$(mktemp "$CODEX_ROOT/.sefi-agents-clean.XXXXXX")" || exit 1
output_file="$(mktemp "$CODEX_ROOT/.sefi-agents-output.XXXXXX")" || exit 1
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

# A symlinked AGENTS.md is refused here rather than followed, for both shapes a link can
# take at this path. A link to a REGULAR FILE would be read through by the strip below
# and then silently replaced by the mv, destroying the link the user maintains; a link to
# a DIRECTORY makes that same mv move the staged block inside the linked directory and
# leave the link in place, so the install would print success while publishing into an
# unrelated tree. The check precedes the read, so neither shape is consulted at all, and
# it matches the profile-loop guards above rather than relying on the directory gate.
[ ! -L "$AGENTS_FILE" ] || {
  echo "install-codex.sh: refusing symlinked AGENTS.md $AGENTS_FILE" >&2
  exit 1
}

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
# Re-verify immediately before the move that replaces the user's AGENTS.md. The awk
# strip above read the live file, so the whole assembly ran after the gate.
refuse_escaped_codex_root || exit 1
sefi_assert_write_target "$AGENTS_FILE" "$CODEX_ROOT_PHYS" \
  "install-codex.sh: refusing to write $AGENTS_FILE" || exit 1
[ ! -L "$AGENTS_FILE" ] || {
  echo "install-codex.sh: refusing symlinked AGENTS.md $AGENTS_FILE" >&2
  exit 1
}
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
  [ ! -L "$agent_profile" ] || {
    echo "install-codex.sh: refusing symlinked agent profile $agent_profile" >&2
    exit 1
  }
  # NEW-3: never read the live profile path. Stage a private copy first, with cp -P
  # (--no-dereference), so the read below can only ever touch a regular file this
  # install owns. A symlink swapped in between the test above and the copy is copied
  # AS a symlink rather than followed, and is caught by the test on the staged copy;
  # a swap after the copy is irrelevant, because the awk below reads the copy and
  # writes a new file that only mv (which replaces, never follows) puts in place.
  agent_read_tmp=""
  if [ -f "$agent_profile" ]; then
    refuse_escaped_codex_agents || exit 1
    sefi_assert_write_target "$agent_profile" "$CODEX_ROOT_PHYS/agents" \
      "install-codex.sh: refusing to write $agent_profile" || exit 1
    agent_read_tmp="$(mktemp "$CODEX_AGENTS_DIR/.sefi-agent-read.XXXXXX")" || exit 1
    cp -P -- "$agent_profile" "$agent_read_tmp" || {
      rm -f -- "$agent_read_tmp"
      echo "install-codex.sh: cannot read agent profile $agent_profile" >&2
      exit 1
    }
    if [ -L "$agent_read_tmp" ] || [ ! -f "$agent_read_tmp" ]; then
      rm -f -- "$agent_read_tmp"
      echo "install-codex.sh: refusing to read a symlinked agent profile $agent_profile" >&2
      exit 1
    fi
  else
    echo "install-codex.sh: cannot apply the model policy to $agent_profile" >&2
    exit 1
  fi
  agent_tmp="$(mktemp "$CODEX_AGENTS_DIR/.sefi-agent.XXXXXX")" || {
    rm -f -- "$agent_read_tmp"
    exit 1
  }
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
  ' "$agent_read_tmp" > "$agent_tmp" || {
    rm -f -- "$agent_read_tmp" "$agent_tmp"
    echo "install-codex.sh: cannot apply the model policy to $agent_profile" >&2
    exit 1
  }
  rm -f -- "$agent_read_tmp"
  # Re-verify after the transform, immediately before the mv.
  refuse_escaped_codex_agents || exit 1
  sefi_assert_write_target "$agent_profile" "$CODEX_ROOT_PHYS/agents" \
    "install-codex.sh: refusing to write $agent_profile" || exit 1
  mv "$agent_tmp" "$agent_profile"
done

echo "install-codex.sh: installed $PLUGIN and updated $AGENTS_FILE"
echo "install-codex.sh: applied the approved Sefi specialist model policy in $CODEX_AGENTS_DIR"
echo "install-codex.sh: start a new Codex session and accept its one-time Sefi hook trust prompt when shown."
print_onboarding
