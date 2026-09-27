#!/usr/bin/env bash
# validate-release-ledger.sh -- reconcile state/release-ledger.md across the six published
# version surfaces (plugin.json, marketplace.json, CHANGELOG, git tag, GitHub release,
# GitHub marketplace index). POSIX-sh body; no python3, no jq -- the Markdown table is
# parsed with awk/grep.
#
# Ported from Demonbane18/astral-orchestrator skills/track-astral-releases/scripts/
# release-ledger.py (MIT): same evidence-priority discipline, the same "common false proof"
# column, and the same strict "partially released until every surface matches" gate.
#
# HARD-FAIL (exit 1):
#   1. within ANY single version group in the ledger (not just the latest), match and
#      mismatch observations do not contradict; a lag observation is permitted only when
#      it is older than that row's expected version;
#   2. a latest-version row's observed value contradicts the on-disk source it names --
#      plugin.json, marketplace.json, or the CHANGELOG.md first versioned heading;
#   3. marketplace.json's two version occurrences (metadata.version, plugins[0].version)
#      disagree with EACH OTHER on disk, regardless of what the ledger observed.
# Also exit 1 on: missing ledger, empty ledger, a missing --ledger/--root value, an
# unrecognized --opt=value joined-form option, an unknown surface token, an unknown
# status token, a non-empty version cell that is not an exact semver (a partial match
# such as 0.5.2.1, 0.6.0-rc1, or 1.2.3.4 is rejected, not silently truncated).
#
# Both spaced (--ledger PATH) and joined (--ledger=PATH) option forms are accepted.
#
# WARN (printed, exit 0): any of the six surfaces is `unobserved` for the latest version.
# --strict also rejects a latest lag or mismatch surface, even when all six were queried.
#
# On success prints: validate-release-ledger: OK (latest <v>, N/6 surfaces observed,
# K warning(s))
#
# Usage: validate-release-ledger.sh [--ledger PATH | --ledger=PATH]
#                                   [--root DIR | --root=DIR] [--strict]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
LEDGER=""
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)
      [ $# -ge 2 ] || { echo "ERROR: --ledger requires a path argument"; echo "validate-release-ledger: 1 error(s)"; exit 1; }
      LEDGER="$2"; shift 2 ;;
    --ledger=*)
      LEDGER="${1#--ledger=}"
      [ -n "$LEDGER" ] || { echo "ERROR: --ledger= requires a non-empty path argument"; echo "validate-release-ledger: 1 error(s)"; exit 1; }
      shift ;;
    --root)
      [ $# -ge 2 ] || { echo "ERROR: --root requires a directory argument"; echo "validate-release-ledger: 1 error(s)"; exit 1; }
      ROOT="$2"; shift 2 ;;
    --root=*)
      ROOT="${1#--root=}"
      [ -n "$ROOT" ] || { echo "ERROR: --root= requires a non-empty directory argument"; echo "validate-release-ledger: 1 error(s)"; exit 1; }
      shift ;;
    --strict) STRICT=1; shift ;;
    --*=*)    echo "ERROR: unrecognized joined-form option '${1%%=*}='"; echo "validate-release-ledger: 1 error(s)"; exit 1 ;;
    *)        shift ;;          # ignore unknown bare args rather than fail the suite
  esac
done
[ -n "$LEDGER" ] || LEDGER="$ROOT/state/release-ledger.md"

CANONICAL_SURFACES="plugin.json marketplace.json changelog git-tag github-release github-marketplace-index"

if [ ! -f "$LEDGER" ]; then
  echo "ERROR: release ledger not found: $LEDGER"
  echo "validate-release-ledger: 1 error(s)"
  exit 1
fi

# --- parse the table: one TSV line per data row (version, surface, expected,
#     observed, status, normalized-version, normalized-observed), header and
#     separator rows dropped, cells trimmed. ---
rows="$(awk -F'|' '
  # norm(v): the bare X.Y.Z only when the whole cell is an exact (optionally
  # v-prefixed) semver. Anchored end-to-end on purpose: a prefix match would let
  # 0.5.2.1 / 0.6.0-rc1 / 1.2.3.4 yield a truncated version that then silently
  # fails the $6==L / $6==G equality checks and drops the row out of every
  # hard-fail and the N/6 count. An exact-only match makes such a cell trip the
  # unparseable-version hard-fail instead of escaping.
  # Each numeric component is (0|[1-9][0-9]*): semver forbids leading zeros, so
  # 00.5.2 / 01.0.0 / 0.05.2 / 1.2.03 fail to parse here and trip the same
  # unparseable-version hard-fail rather than normalizing into a phantom second
  # version group.
  # Spelled without ERE alternation (split + substr checks) for maximal awk
  # portability. Runs ONCE inside this single parse pass (fields $6/$7), so the
  # hot loops below do zero per-row forks: under Git Bash on Windows each forked
  # grep/sed/head pipeline costs ~0.1s, and ~460 of them (one per row, per
  # version group) pushed --strict past a 25s timeout (exit 124).
  # Failure sentinel is "-": the downstream `read` loops split on IFS tabs, and
  # `read` silently collapses an EMPTY middle field into its neighbours (a row
  # whose normalization failed would shift $7 into $6 and escape every check).
  # "-" can never collide with a real normalized version (digits and dots only),
  # so every field stays non-empty and positional.
  function norm(v,   w, n, p) {
    w = v; sub(/^v/, "", w)
    if (w !~ /^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$/) return "-"
    n = split(w, p, "[.]")
    if (n != 3) return "-"
    if ((p[1] != "0" && substr(p[1], 1, 1) == "0") || \
        (p[2] != "0" && substr(p[2], 1, 1) == "0") || \
        (p[3] != "0" && substr(p[3], 1, 1) == "0")) return "-"
    return w
  }
  /^[[:space:]]*\|/ {
    for (i = 1; i <= NF; i++) { gsub(/^[[:space:]]+/, "", $i); gsub(/[[:space:]]+$/, "", $i) }
    if ($2 == "" || $2 == "version") next          # blank cell or header row
    # GFM separator row ONLY when EVERY non-empty cell is dashes/colons (:--- / :--: / ---:
    # alignment markers). A real data row whose version cell ALONE happens to be :-: / --: /
    # :-- is NOT a separator -- it must reach the exact-semver normalization and
    # trip the unparseable-version hard-fail, not vanish before hard-fail 1,
    # hard-fail 2, and the N/6 count.
    sep = 1; nonempty = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "") continue
      nonempty = 1
      if ($i !~ /^:?-+:?$/) { sep = 0; break }
    }
    if (sep && nonempty) next
    print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" norm($2) "\t" norm($5)
  }
' "$LEDGER")"

if [ -z "$rows" ]; then
  echo "ERROR: $LEDGER has no data rows"
  echo "validate-release-ledger: 1 error(s)"
  exit 1
fi

errors=0
err() { echo "ERROR: $1"; errors=$((errors + 1)); }
is_older_version() {
  local observed="$1" expected="$2"
  [ "$observed" != "-" ] && [ "$observed" != "$expected" ] \
    && [ "$(printf '%s\n%s\n' "$observed" "$expected" | sort -V | head -1)" = "$observed" ]
}

# --- structural checks on every row ($6/$7 carry the parse-time normalization,
#     so this loop forks nothing per row) ---
while IFS="$(printf '\t')" read -r version surface expected observed status nver nobs; do
  [ -z "$version" ] && continue
  case " $CANONICAL_SURFACES " in
    *" $surface "*) : ;;
    *) err "unknown surface token '$surface' (row version $version)" ;;
  esac
  # a non-empty version cell that does not yield a semver silently exempts the row from
  # latest/latest_rows -- hard-fail it, symmetric with the surface/status checks above.
  # ("-" is the parse-time normalization-failure sentinel; see norm().)
  if [ "$nver" = "-" ]; then
    err "unparseable version cell '$version' (surface $surface) -- not a semantic version"
  fi
  case "$status" in
    match|lag|mismatch|unobserved) : ;;
    *) err "unknown status '$status' for $surface (row version $version)" ;;
  esac
  if [ "$status" = "lag" ] && ! is_older_version "$nobs" "$nver"; then
    err "lag row for $surface (version $version) must observe an older semantic version than expected $nver"
  fi
done <<EOF
$rows
EOF

# --- latest version = highest normalized semver in the version column ---
latest="$(printf '%s\n' "$rows" | awk -F'\t' '$6 != "-" { print $6 }' | sort -V | tail -1)"
if [ -z "$latest" ]; then
  echo "ERROR: no semantic version found in the ledger's version column"
  echo "validate-release-ledger: 1 error(s)"
  exit 1
fi

latest_rows="$(printf '%s\n' "$rows" | awk -F'\t' -v L="$latest" '$6 == L')"
# The ledger is append-only: later observations supersede earlier ones for the same
# surface in the same target-version group. Preparation still inspects all rows above;
# completion and warnings use this newest observation per surface.
latest_surface_rows="$(printf '%s\n' "$latest_rows" | awk -F'\t' '{ latest[$2] = $0 } END { for (surface in latest) print latest[surface] }')"

# --- hard-fail 1: within ANY single version group, match/mismatch observations must not
#     contradict. A lag row is already checked above to be older than its expected target,
#     so it records a truthful prepublication surface without becoming a false
#     cross-surface contradiction. This remains per-version-group, not latest-only. ---
all_groups="$(printf '%s\n' "$rows" | awk -F'\t' '$6 != "-" { print $6 }' | sort -uV)"
for grp in $all_groups; do
  grp_observed="$(printf '%s\n' "$rows" | awk -F'\t' -v G="$grp" '
    $6 == G && ($5 == "match" || $5 == "mismatch") && $7 != "-" { print $7 }
  ' | sort -u)"
  g_distinct="$(printf '%s\n' "$grp_observed" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "${g_distinct:-0}" -gt 1 ]; then
    err "surfaces disagree on the version claim $grp: observed $(printf '%s' "$grp_observed" | paste -sd',' -)"
  fi
done

# --- hard-fail 2: a latest-version row contradicts the on-disk source it names ---
disk_plugin=""; disk_changelog=""; disk_marketplace=""
PJ="$ROOT/plugins/sefi-core/.claude-plugin/plugin.json"
MP="$ROOT/.claude-plugin/marketplace.json"
CL="$ROOT/CHANGELOG.md"
[ -f "$PJ" ] && disk_plugin="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$PJ" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -f "$CL" ] && disk_changelog="$(grep -m1 -oE '^##[[:space:]]*\[[0-9]+\.[0-9]+\.[0-9]+\]' "$CL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ -f "$MP" ]; then
  mp_all="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$MP" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  disk_marketplace="$(printf '%s\n' "$mp_all" | sort -u | sed '/^$/d')"
  mp_distinct="$(printf '%s\n' "$disk_marketplace" | sed '/^$/d' | wc -l | tr -d ' ')"
  # marketplace.json self-disagreement: metadata.version and plugins[0].version differ
  # FROM EACH OTHER on disk. Hard-fail here, independent of what any ledger row observed --
  # a membership test against the {both} set (below) lets either occurrence's value pass
  # even when the two occurrences contradict each other (the slice's own "common false
  # proof": references/release-surfaces.md, SKILL.md).
  if [ "${mp_distinct:-0}" -gt 1 ]; then
    err "marketplace.json self-disagreement on disk: the two version occurrences differ ($(printf '%s' "$disk_marketplace" | paste -sd',' -)) -- $MP"
  fi
fi

while IFS="$(printf '\t')" read -r version surface expected observed status nver nobs; do
  [ -z "$version" ] && continue
  [ "$status" = "unobserved" ] && continue
  ov="$nobs"
  [ -z "$ov" ] && continue
  [ "$ov" = "-" ] && continue
  case "$surface" in
    plugin.json)
      [ -n "$disk_plugin" ] && [ "$ov" != "$disk_plugin" ] \
        && err "ledger row says plugin.json observed $ov, but $PJ on disk is $disk_plugin" ;;
    changelog)
      [ -n "$disk_changelog" ] && [ "$ov" != "$disk_changelog" ] \
        && err "ledger row says changelog observed $ov, but the CHANGELOG.md top heading on disk is $disk_changelog" ;;
    marketplace.json)
      if [ -n "$disk_marketplace" ] && ! printf '%s\n' "$disk_marketplace" | grep -qxF "$ov"; then
        err "ledger row says marketplace.json observed $ov, but $MP on disk has $(printf '%s' "$disk_marketplace" | paste -sd',' -)"
      fi ;;
  esac
done <<EOF
$latest_rows
EOF

if [ "$errors" -ne 0 ]; then
  echo "validate-release-ledger: $errors error(s) -- latest version claim $latest is contradicted"
  exit 1
fi

# --- warnings: surfaces unobserved in their newest latest-version observation ---
observed_surfaces="$(printf '%s\n' "$latest_surface_rows" | awk -F'\t' '$5 != "unobserved" { print $2 }' | sort -u | sed '/^$/d')"
n_observed="$(printf '%s\n' "$observed_surfaces" | sed '/^$/d' | wc -l | tr -d ' ')"
warnings=0
for s in $CANONICAL_SURFACES; do
  if ! printf '%s\n' "$observed_surfaces" | grep -qxF "$s"; then
    echo "WARN: surface '$s' is unobserved for the latest version ($latest)"
    warnings=$((warnings + 1))
  fi
done

echo "validate-release-ledger: OK (latest $latest, ${n_observed:-0}/6 surfaces observed, $warnings warning(s))"
if [ "$STRICT" -eq 1 ] && [ "$warnings" -ne 0 ]; then
  echo "validate-release-ledger: strict completion requires all 6 surfaces to match" >&2
  exit 1
fi
strict_nonmatches="$(printf '%s\n' "$latest_surface_rows" | awk -F'\t' '$5 != "match" { print $2 "=" $5 }' | sort -u | paste -sd',' -)"
if [ "$STRICT" -eq 1 ] && [ -n "$strict_nonmatches" ]; then
  echo "validate-release-ledger: strict completion requires all 6 surfaces to match (non-match: $strict_nonmatches)" >&2
  exit 1
fi
exit 0
