<p align="center"><img src="docs/assets/logo.png" alt="Sefi Automates" width="200"></p>

<h1 align="center">sefi-agents</h1>
<p align="center"><strong>A software company in a plugin.</strong></p>

<p align="center">
<a href="https://github.com/xsefirosus/sefi-agents/actions/workflows/ci.yml"><img src="https://github.com/xsefirosus/sefi-agents/actions/workflows/ci.yml/badge.svg" alt="ci"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license: MIT"></a>
<a href="#faq"><img src="https://img.shields.io/badge/runtime%20deps-zero-brightgreen.svg" alt="runtime deps: zero"></a>
<a href="#works-with-your-harness"><img src="https://img.shields.io/badge/runs%20on-Claude%20Code%20%7C%20Hermes%20%7C%20OpenCode%20%7C%20Codex-555.svg" alt="runs on"></a>
</p>

Thirteen AI agents -- a planner, a builder, a reviewer, a security checker, a writer,
and more -- that work as a team: plan, build, check, and remember, with spending limits
and a human approving every merge.

One install, no separate setup: no database, no server to run, nothing else to
download. Just this plugin, plus the AI tool you already use.

**Install for Claude Code:**

```
/plugin marketplace add xsefirosus/sefi-agents
/plugin install sefi-core@sefi-agents
/sefi:init
```

Using OpenCode, Hermes Agent, or Codex instead? The install steps are different for each
-- see [Where it runs](#works-with-your-harness) below, don't run the commands above.

Or hand the setup to any coding agent -- this one detects which tool you're using and
installs the right way for it, Claude Code or otherwise:

> Help me set up sefi-agents by following
> https://raw.githubusercontent.com/xsefirosus/sefi-agents/main/Install.md

**Contents:** [Why this exists](#why-this-exists) -- [How it compares](#how-it-compares) --
[The team](#the-team-13-agents) -- [The skills](#the-skills-11) --
[How a request gets done](#how-a-request-actually-gets-done) --
[Memory](#memory-that-survives-the-session) -- [Where it runs](#works-with-your-harness) --
[Safety rules](#safety-rails-all-of-them-in-one-place) -- [Proof](#proof) -- [FAQ](#faq) --
[Contributing](#contributing) -- [License](#license)

## Why this exists

Most AI coding setups fail the same three ways:

- **The AI grades its own homework.** The same model that writes the code also reviews
  it, so it rarely catches its own mistakes.
- **Spending gets out of control.** Nothing stops a task from running (and costing money)
  far longer than it should.
- **Every conversation starts from zero.** Whatever the AI learned yesterday is gone
  today, because nothing wrote it down.

We hit all three problems first, in the author's earlier version of this project. That
post-mortem is public, not hidden: [docs/ANTIPATTERNS.md](docs/ANTIPATTERNS.md) lists each
failure next to the fix that now prevents it.

**Where these ideas come from.** The generator/verifier split matches current
graph-engineering practice's "diamond pattern" -- split, parallel workers, a separate
verifier node, merge, never a worker verifying its own branch. The qa-engineer's blind,
named-bar review is the same idea Matt Shumer's "Gauntlet Loop" popularized, with one
deliberate difference: this repo caps it (PASS/REJECT under a fixed retry limit), rather
than looping until a critic is satisfied. And the whole shape -- a WIP limit on parallel
work, a pull-based `state/`/`inbox/` board, CI that stops at a pull request instead of
deploying -- is Kanban and CI/CD, with the CD half cut off on purpose.

## How it compares

Three real incidents from this project's own history, no made-up "after" numbers -- full
history in [CHANGELOG.md](CHANGELOG.md):

<img src="docs/assets/comparison.svg" alt="Three real incidents, without sefi-agents versus with sefi-agents" width="100%">

(Usage is measured in "tokens" -- small chunks of text AI providers use to price and
limit how much a task can do.)

## The team (13 agents)

Thirteen AI agents, each with one job and a written contract for what it may touch, run,
and change -- grouped by how strong a model each one gets:

**Reviewers (strongest model):** `qa-engineer` approves or rejects finished work with
evidence -- `security-engineer` checks anything touching logins, secrets, or outside
input.

**Builders (mid-strength model):** `engineering-manager` routes work and never codes --
`product-manager` turns a goal into a checkable plan -- `software-engineer` builds one
piece at a time, in its own workspace -- `ui-ux-designer` handles interface work --
`devops-engineer` runs CI/CD and scheduling -- `solutions-architect` designs automations
(n8n, Make, GoHighLevel).

**Support crew (cheapest model):** `research-analyst` gathers context -- `support-engineer`
sorts incoming issues -- `knowledge-manager` tends the memory, never deletes -- `technical-writer`
writes docs, claims double-checked -- `prompt-engineer` clarifies a raw request first.

## The skills (11)

Playbooks an agent loads only when the task needs it, not a 14th agent -- most load
automatically, a few you call by name, and a named skill can never chain another one, so
it can't silently escalate on its own:

**Always relevant:** `sefi-orchestration` (routes every request) -- `anti-hallucination`
(the core honesty rule: say "unknown" instead of guessing, CI-enforced everywhere).

**Building & reviewing:** `frontend-design`, `backend-design`, `security-review` --
interface, API, and security best practices.

**Memory & process:** `memory-protocol`, `loop-engineering`, `retro-improve` -- how
memory is read and written, the five-step loop pattern, and small self-improvements.

**Specialized:** `technical-writing`, `n8n-workflow-design`, `terse-mode`.

## How a request actually gets done

Three things happen, not one: every request runs the left track below by you typing it;
completely separately and unattended, the middle track runs the same build-and-check chain
once a day against failed builds and new issues; and once a week, the right track looks at
how things went and proposes small fixes to the agents themselves:

<img src="docs/assets/how-it-works.svg" alt="How sefi-agents works: the interactive request cycle on the left, the daily morning-triage loop in the middle, and the weekly self-improvement loop on the right, feeding back into the same agents" width="100%">

- Spending limits and tool checks apply at every step, not just at the end (see
  [Safety rails](#safety-rails-all-of-them-in-one-place)) -- and token efficiency is built
  into how each agent works: one-shot research windows, replies read wherever the answer
  lands instead of re-asking, short status updates by default (`terse-mode`).
- The right track stays bounded on purpose -- at most 3 sentences changed per file per
  week, every fix checked by qa-engineer *before* it ships -- and logs "nothing to change"
  rather than fire without real evidence.
- A "loop" is this same chain on a schedule instead of typed by you: **morning-triage**
  (daily) and **weekly-retro** (weekly, the right track above) both still stop at a pull
  request. Every loop must declare five things -- find work, hand off, check, remember,
  reschedule -- or it's rejected automatically; `/sefi:loop-new` builds your own.

## Memory that survives the session

Plain markdown notes in your project's own `memory/` folder, git-committed by default --
readable, searchable, and visible in your pull requests. No database, no external
service. A new session loads a short index automatically (capped at 1,500 characters);
only the knowledge-manager writes, at the end of a work cycle, after stripping anything
that looks like a password or secret.

Related projects can now see each other's notes, without merging them: on a real local
machine (never on a cloud/CI session), each project's saved notes are additionally
mirrored to one shared, per-user folder outside any repo, kept separate by project. A
session only opens another project's notes when you explicitly reference that project --
never a background scan -- so nothing gets pulled in you didn't ask for. This project uses
its own memory system on itself, but a fresh install starts empty.

## Works with your harness

| Tool | How to install | Notes |
|---|---|---|
| Claude Code | plugin install (above) | full support |
| OpenCode | [adapters/OPENCODE.md](adapters/OPENCODE.md) | can run unattended for scheduled jobs |
| Hermes Agent | [adapters/HERMES.md](adapters/HERMES.md) | one command; 11 of 13 skills install automatically, 2 need one manual step (see FAQ) |
| Codex | [adapters/CODEX.md](adapters/CODEX.md) | plugin marketplace install |

## Safety rails (all of them, in one place)

- The agent that writes code never approves its own work -- a separate reviewer checks
  it with real evidence.
- A security checker reviews any change touching sensitive code.
- Automated checks the AI can't skip: tests and linting, plan structure, handoffs between
  agents, and tool availability before a job starts.
- Spending limits: per task, per day, and overall. If spending can't be measured, the
  system stops and says so instead of assuming it's fine.
- Anything the system isn't sure about goes to a review folder (`inbox/`) for you to
  decide.
- Nothing merges or deploys by itself. Every automated job stops at a pull request and
  waits for you.

## Proof

This project checks itself. The same checks run on every push (badge above), and you can
run them yourself, in one command:

```
$ bash plugins/sefi-core/scripts/ci/run-all.sh
validate-agents: OK (13 agent files validated)
validate-skills: OK (11 SKILL.md validated)
validate-doc-counts: OK (agents=13 skills=11 commands=6 loops=2, all prose matches disk)
validate-loops: OK (2 loop spec(s) validated, plus 2 in this project's loops/)
validate-budget: OK (all caps present and bounded)
validate-config-wired: OK (12 config keys, all wired)
validate-no-personal-paths: OK (no personal paths in shipped files)
validate-no-orphans: OK (references, templates, agents all wired)
validate-links: OK (58 files scanned, all repo-path references resolve; bare script names checked)
validate-script-refs: OK (43 files scanned, every scripts/*.sh reference carries ${CLAUDE_PLUGIN_ROOT}/)
validate-routing: OK (routing-table agents exist, fixtures resolve, no duplicate triggers)
validate-model-map: OK (13 agents, 4 harnesses, 41 scripts parse; 2 warning(s))
validate-adapters: OK (install-hermes.sh skill list matches disk, adapter doc paths resolve)
check-unicode-safety: OK (124 files scanned, ASCII-clean)
validate-token-budget: OK (all within token budgets; agents total 8316 words)
test-scripts: OK (148 passed)
test-integration: OK (30 passed) -- full loop skeleton executed end to end
CI: all validators passed
```

- The last two lines matter most: one proves every script works by itself, the other
  proves the whole cycle works together, end to end, in a real test project -- with a real
  check that nothing merged itself.
- This proves the machinery works, not that the AI always makes good calls -- every
  agent's part in that test is scripted, not judged.
- Every agent and skill has a length limit, and going over it fails the build. Exact
  numbers change as the project grows -- run the command yourself instead of trusting this
  snapshot.

## FAQ

**Do I need an expensive AI model?** No. Cheap models are fine -- scripts handle the
repetitive checking, so the AI is only doing the creative part. In earlier testing, a
free model only succeeded on its own about 45% of the time, and the review step still
caught the rest.

**Does it work on Windows?** Yes -- it's tested on both Windows (Git Bash) and Linux.

**Where does my data go?** Nowhere. Nothing here calls home or tracks you. If you use a
free trial of some AI model, check [adapters/HERMES.md](adapters/HERMES.md) first: don't
run private code through a model that might learn from your input.

**Can it merge or deploy something by itself?** No. It opens a pull request and stops,
every time -- that rule is checked automatically, not just written down.

**What happens when the AI doesn't know something?** It says so, instead of guessing.
That rule is enforced automatically across every agent and skill.

**Why didn't every skill install automatically on Hermes?** Hermes scans skills for
risky-looking content, and two of ours get flagged by mistake -- they *describe* risky
patterns in order to guard against them, and the scanner can't yet tell the difference.
The other 11 skills install fine; the installer prints the two-step manual fix for the
rest. See [adapters/HERMES.md](adapters/HERMES.md) section 8.

**Do I need Obsidian?** No. The memory notes are plain text files; Obsidian just makes
them nicer to browse.

**What about deploy and maintenance roles, like a real software company has?**
`devops-engineer` already covers deploy (CI/CD, scheduling) up to the pull-request
boundary -- it never merges or deploys itself, same as everything else here. A
maintenance role (dependency upgrades, deprecations, flaky tests) is a real gap; the
proposed fix is a `dependency-upkeep` loop chaining `support-engineer` -> `software-engineer`
-> `qa-engineer`, the same PR-only pattern as the two shipped loops -- not built yet.

## Contributing

Run the full check before opening a pull request:

```
bash plugins/sefi-core/scripts/ci/run-all.sh
```

Those checks are the actual contribution guide: length limits, short descriptions,
nothing broken or unused, and the honesty rule present in every agent and skill.

This repo ships broad-auto-allow permission defaults for Claude Code, OpenCode, and Codex
(`.claude/settings.json`, `opencode.json`, `.codex/config.toml`) so an unattended session
doesn't stall on a routine prompt -- with a deny list for force-push, hard resets, branch
deletion, `rm -rf`, and credential files. Known gaps stated in those files themselves, not
hidden: Codex has no per-command deny list, and Hermes gets no config at all since it
doesn't read one.

## License

MIT. See [LICENSE](LICENSE).
