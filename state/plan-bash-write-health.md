## Objective
Make the Bash-write security gate and the CI worked-example extraction trust only a JSON
parser that actually RUNS -- resolving jq -> python3 -> python -> py with a smoke test on
each candidate -- so the Microsoft Store python3 alias stub on this Windows dev machine
(present via `command -v`, prints "Python was not found", exits 1) no longer fails the
gate OPEN, while the documented fail-open for hosts with NO working parser stays intact.

Approaches considered, finalized on A:
- Approach A (chosen, ~1 day, low risk): a shared health-checked resolver chain
  (`json_tool()` in check-bash-write.sh; the same python3/python/py loop in the
  test-scripts.sh extraction). Only the parser-SELECTION path changes; the per-outcome
  fail-open/fail-closed semantics are byte-identical, and four shim regression cases pin
  every boundary.
- Approach B (rejected, ~1 hour): treat a nonzero python exit as a hard failure and exit 2
  ("fail closed on broken parser"). This punishes the host instead of fixing the probe: a
  host whose only parser is broken would block every Bash call, breaking agents entirely --
  exactly the failure the header's fail-open rationale (check-bash-write.sh lines 86-91)
  exists to avoid. It also cannot distinguish "parser crashed" from "payload had no
  command". The fix is a better probe, not a stricter verdict.

## Steps
- [x] 1. Add the health-checked resolver `json_tool()` to plugins/sefi-core/scripts/check-bash-write.sh and rewire both extractors: insert `json_tool()` immediately after line 42 (`INPUT="$(cat)"`), replace the bodies of `extract_command()` (lines 44-63) and `extract_agent_type()` (lines 65-84) per snippet A1, and reword the fail-open rationale comment at lines 86-91 (first sentence -> "No WORKING JSON parser available, no agent_type, or no command: fail OPEN in every case."; "lacks jq and python3" -> "lacks a working jq/python3/python/py"). The `[ -z "$AGENT_TYPE" ] && exit 0` (line 93), `[ -z "$CMD" ] && exit 0` (line 96), and the write-shape detector at line 142 (`(python3?|node|ruby|perl)[[:space:]]+-[ce]`) are UNCHANGED. (needs: -)
- [x] 2. Rework the worked-example extraction in plugins/sefi-core/scripts/ci/test-scripts.sh (lines 603-609) per snippet A2: define `extract_plan_example()` immediately BEFORE line 603 and replace the `python3 - "$PV" <<'EXTRACT' ... EXTRACT` block with a single call `extract_plan_example "$PV"`. The existing `if [ -f "$PV/state/plan-example.md" ]` block (lines 611-638) is untouched; this fixes line 637's "could not extract the worked example". (needs: -)
- [x] 3. Add the shim-based regression block from snippet A3 to plugins/sefi-core/scripts/ci/test-scripts.sh, inserted after the no-agent_type test (line 849) and before `unset CLAUDE_PLUGIN_ROOT` (line 851). Cases: (a) broken python3 + working python -> gate still blocks sed -i (exit 2); (b) broken python3 + working python -> worked-example extraction still succeeds; (c) no working parser at all (jq, python3, python, py all broken) -> documented fail-open exit 0 preserved. The pre-existing `expect_bw` cases (lines 836-845) and the no-agent_type case (line 849) must keep passing unchanged on the normal PATH -- that is case (d), the nothing-regressed half. (needs: 1, 2)
- [x] 4. Add the 0.3.9 CHANGELOG entry at the top of CHANGELOG.md (above line 6, `## [0.3.8] - 2026-08-18`), one `### Fixed` item, stating: the Bash-write gate and the CI worked-example extraction trusted `command -v python3` presence without checking the interpreter runs; on this Windows dev machine python3 is the Microsoft Store alias stub (present, prints "Python was not found", exits nonzero), so `extract_command()`/`extract_agent_type()` returned empty and sed -i/tee failed OPEN (exit 0 instead of 2) while a working Python 3.11.15 sat on PATH as `python`; the same root cause reddened local CI (3 failed / 89 passed: test-scripts.sh line 603's swallowed extraction -> "could not extract the worked example", and the two expected exit-2 cases). The fix is a health-checked resolver chain (jq -> python3 -> python -> py, smoke-tested before trust) used by both extractors and the extraction; the documented fail-open for hosts with no working parser is preserved and pinned by a regression case. Note CI parity: ubuntu runners have a healthy python3 (and jq), so their non-shim behavior is unchanged; the new shim tests force the broken-python3 path deterministically there. Mention 3 new regression cases and record the ACTUAL local assertion counts (they vary by platform because of the timeout/shellcheck/ccusage skips -- capture the real numbers from your run, do not copy a fixed pair). No footer link is needed (0.3.x entries carry none). (needs: 3)
- [x] 5. Verify end to end from the repo root: (1) run `bash plugins/sefi-core/scripts/ci/run-all.sh` and confirm it exits 0 with test-scripts.sh printing `test-scripts: OK (` and zero `FAIL:` lines, including the five labels from Done Criteria; (2) confirm the live reproduction on THIS machine -- `python3 -c 'import json,sys'` exits nonzero (Store stub) yet `printf '{"agent_type":"engineering-manager","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' | CLAUDE_PLUGIN_ROOT=plugins/sefi-core bash plugins/sefi-core/scripts/check-bash-write.sh` exits 2; (3) confirm CI parity by reasoning, not by running GitHub: with a healthy python3/jq on ubuntu the resolver picks the same tool the old code picked (jq, else python3), so shipped behavior there is unchanged, and the shim tests are self-contained. (needs: 3, 4)

## Files Touched
plugins/sefi-core/scripts/check-bash-write.sh; plugins/sefi-core/scripts/ci/test-scripts.sh; CHANGELOG.md

## Requires Tools
bash, coreutils (mktemp, printf, chmod, env, rm), grep, awk, sed, python (any of python3/python/py that actually runs -- the suite must pass without jq; that absence is the point)

## Risks
- The fail-open boundary is the design constraint, not a bug: hosts with NO working parser must keep exit 0 (header rationale, check-bash-write.sh lines 86-91). Step 3 case (c) pins it; a builder who "improves" the gate to fail closed on a parser-less host breaks every agent on minimal hosts and will be caught by that case.
- Do NOT touch line 142's `(python3?|node|ruby|perl)[[:space:]]+-[ce]` pattern -- it is the write-SHAPE detector for inline interpreters, not a parser probe; "python3?" there intentionally matches both `python` and `python3`.
- Assertion counts vary by platform (timeout/shellcheck/ccusage skips), so the CHANGELOG and Done Criteria judge on zero FAIL lines and the named labels, never a fixed count.
- The exec-shim must quote the captured interpreter path -- this machine's Windows username "Mary Rose" contains a space.
- Cases (a)/(b) assume at least one working interpreter exists on the host (`real_py` non-empty); this machine (`python`) and ubuntu CI (`python3`) both qualify.
- memory/decisions/ is empty -- no prior decision constrains this plan; the fail-open rationale lives in the script header itself.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` exits 0, its test-scripts.sh output shows `test-scripts: OK (` with zero `FAIL:` lines, and the run contains all five labels: "broken python3 + working python: sed -i still blocked (exit 2)"; "worked-example extraction survives a broken python3 (working python fallback)"; "no working parser at all: documented fail-open preserved (exit 0)"; "engineering-manager: sed -i on a state file is blocked (exit 2)"; "qa-engineer: tee into a state file is blocked (exit 2)". Additionally, on this machine, `python3 -c 'import json,sys'` exits nonzero (Store stub) while `printf '{"agent_type":"engineering-manager","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' | CLAUDE_PLUGIN_ROOT=plugins/sefi-core bash plugins/sefi-core/scripts/check-bash-write.sh` exits 2.

## Appendix: reference snippets
Snippets A1-A3 referenced by Steps 1-3. Copy each verbatim into the file and position named
in its step; keep the heredoc terminators (`EXTRACT`) at column 0 when pasting snippet A2.

```bash
# --- A1: health-checked resolver + rewired extractors for check-bash-write.sh ---
json_tool() {
  local t
  for t in jq python3 python py; do
    if command -v "$t" >/dev/null 2>&1; then
      case "$t" in
        jq) printf '{}' | jq -e . >/dev/null 2>&1 || continue ;;
        *)  "$t" -c 'import json,sys' >/dev/null 2>&1 || continue ;;
      esac
      printf '%s' "$t"
      return 0
    fi
  done
  return 1
}

extract_command() {
  local t out=""
  t="$(json_tool)" || { printf ''; return 0; }
  if [ "$t" = jq ]; then
    out="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    printf '%s' "$out"; return 0
  fi
  out="$(printf '%s' "$INPUT" | "$t" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    sys.stdout.write(str(data.get("tool_input", {}).get("command", "")))
except Exception:
    pass
' 2>/dev/null || true)"
  printf '%s' "$out"
}

extract_agent_type() {
  local t out=""
  t="$(json_tool)" || { printf ''; return 0; }
  if [ "$t" = jq ]; then
    out="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
    printf '%s' "$out"; return 0
  fi
  out="$(printf '%s' "$INPUT" | "$t" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    sys.stdout.write(str(data.get("agent_type", "")))
except Exception:
    pass
' 2>/dev/null || true)"
  printf '%s' "$out"
}
```

````bash
# --- A2: extract_plan_example() for test-scripts.sh (replaces lines 603-609's call) ---
extract_plan_example() {
  # extract_plan_example <dest-dir> -- write <dest-dir>/state/plan-example.md from
  # product-manager.md's worked example, using the first WORKING python (python3,
  # then python, then py). `command -v` alone cannot tell the Microsoft Store
  # python3 alias stub from a real interpreter; each candidate is smoke-tested.
  # Returns 0 when the file was written.
  local dest="$1" py=""
  for t in python3 python py; do
    if command -v "$t" >/dev/null 2>&1 && "$t" -c 'import json,sys' >/dev/null 2>&1; then
      py="$t"; break
    fi
  done
  [ -n "$py" ] || return 1
  ( cd "$ROOT" && "$py" - "$dest" <<'EXTRACT' 2>/dev/null
import sys, pathlib, re
t = pathlib.Path("plugins/sefi-core/agents/product-manager.md").read_text()
m = re.search(r'## Worked example.*?```markdown\n(.*?)```', t, re.S)
if m:
    pathlib.Path(sys.argv[1] + "/state/plan-example.md").write_text(m.group(1))
EXTRACT
  )
}
````

```bash
# --- A3: shim-based regression block for test-scripts.sh, inserted after line 849 ---
# The health-check fix (2026-08-18): `command -v python3` is presence-only, and this
# host's python3 is the Microsoft Store alias stub -- present, prints "Python was
# not found", exits 1 -- so the extractors returned empty and the gate failed OPEN
# (sed -i/tee exited 0, not 2; CI reddened 3 failed / 89 passed). Three cases pin
# the fix and its boundary, deterministically, on any host with bash + coreutils.
PYSHIM="$(mktemp -d)"
real_py=""
for t in python3 python py; do
  if command -v "$t" >/dev/null 2>&1 && "$t" -c 'import json,sys' >/dev/null 2>&1; then
    real_py="$(command -v "$t")"; break
  fi
done
mkpy() {
  # mkpy <name> <body> -- write a shim executable into PYSHIM.
  printf '#!/bin/sh\n%s\n' "$2" > "$PYSHIM/$1"
  chmod +x "$PYSHIM/$1"
}
mkpy jq 'exit 1'
mkpy python3 'exit 1'
if [ -n "$real_py" ]; then
  mkpy python "exec \"$real_py\" \"\$@\""
fi

# (a) broken python3 + working python -> the gate still blocks sed -i (exit 2).
got=0
printf '{"agent_type":"engineering-manager","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' \
  | env PATH="$PYSHIM:$PATH" bash "$CBW" >/dev/null 2>&1 || got=$?
if [ "$got" -eq 2 ]; then
  ok "broken python3 + working python: sed -i still blocked (exit 2)"
else
  bad "broken python3 + working python: sed -i expected exit 2, got $got"
fi

# (b) broken python3 + working python -> the worked-example extraction still
# succeeds (the CI-red "could not extract the worked example" failure).
EXB="$(mktemp -d)"; mkdir -p "$EXB/state"
if PATH="$PYSHIM:$PATH" extract_plan_example "$EXB" && [ -f "$EXB/state/plan-example.md" ]; then
  ok "worked-example extraction survives a broken python3 (working python fallback)"
else
  bad "worked-example extraction failed under a broken python3 shim"
fi
rm -rf "$EXB"

# (c) no working parser at all (jq, python3, python, py all broken) -> the
# documented fail-open exit 0 is preserved, not silently regressed.
mkpy python 'exit 1'
mkpy py 'exit 1'
got=0
printf '{"agent_type":"engineering-manager","tool_input":{"command":"sed -i s/a/b/ state/foo.md"}}' \
  | env PATH="$PYSHIM:$PATH" bash "$CBW" >/dev/null 2>&1 || got=$?
if [ "$got" -eq 0 ]; then
  ok "no working parser at all: documented fail-open preserved (exit 0)"
else
  bad "no working parser: expected fail-open exit 0, got $got"
fi
rm -rf "$PYSHIM"
```