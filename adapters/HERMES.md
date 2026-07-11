# Running sefi-agents on Hermes Agent (free-model mode)

Hermes runs the roster on a free model. Canonical agent/skill/command bodies live under
`plugins/sefi-core/`; this adapter only maps the runtime differences and never duplicates
them. The narrow action map is `skills/sefi-orchestration/references/harness-actions.md`.

## 1. Point Hermes at OpenCode Zen (OpenAI-compatible)
- Base URL: `https://opencode.ai/zen/v1`
- Model: `deepseek-v4-flash-free` (200K context, 128K output, $0 during the free window)
- Paid fallback: `deepseek-v4-flash` (~$0.14 / $0.28 per M input/output)

```sh
hermes config set provider.base_url https://opencode.ai/zen/v1
hermes config set provider.model    deepseek-v4-flash-free
hermes config set provider.api_key  "$OPENCODE_ZEN_API_KEY"
```

Precedent: a predecessor system already ran Hermes on an OpenCode Zen free model
(`mimo-v2.5-free`), so this pairing is proven, not speculative.

## 2. Caveats (the caps and the qa-engineer are load-bearing here, not garnish)
- Free-window models may train on submitted data -- never run client or proprietary code
  through them.
- Rate limits make the budget caps and `max_retries` mandatory, not optional.
- Run overnight loops via cloud CI or `hermes cron`, not an always-on local process.
- Calibrate expectations: a predecessor system's tracked free-model dispatch success was ~45%, workable
  only because gates and human checkpoints catch the other half.

## 3. Sync skills
Copy `plugins/sefi-core/skills/` into Hermes' skills path (adjust to your install):
```sh
cp -r plugins/sefi-core/skills/* "$HERMES_HOME/skills/"
```

## 4. Roster
The roster maps to Hermes subagent delegation. `model:` and `disallowedTools:` are advisory
on Hermes, so treat the whitelist as a soft contract; the gates are the hard enforcement.

## 5. Scheduling
Loop triggers map to `hermes cron`.

## 6. Self-improvement coexistence
Hermes' curator touches only its own created skills; sefi's retro loop edits only
`managed-by: sefi-agents` files. They are disjoint by construction. If you prefer, set
`improvement.enabled: false` in `sefi.config.yml` and let the host own learning.

## 7. Local gateway + delegate_task facts (live-verified in a predecessor system)
Every constraint below was discovered by hitting it.

| Fact | Detail |
|---|---|
| Gateway | local OpenAI-compatible: `POST http://localhost:8642/v1/chat/completions` (bearer `HERMES_API_KEY`); `GET /v1/capabilities` = 5s health probe; `GET /v1/skills` = skill list; responses carry a real `usage` block -- record it |
| Dispatch | prompt-instructed, not API-called: instruct Hermes' agent to call its own `delegate_task(tasks=[{goal,context,toolsets,...}], role="orchestrator", background=true)`, tasks array inlined verbatim |
| Reserved `role` | agent-hierarchy field ("orchestrator" / "leaf") -- never reuse for specialist type (collision silently coerces to 'leaf'); use `specialist_role`. `tasks` is required |
| Concurrency | `max_concurrent_children = 3` (hard cap). Batch client-side to <= 3 per call -- never prompt-side (a predecessor's self-batching hit 1.36M tokens and re-ran completed tasks) |
| Timeout | delegation gets its own longer budget (900s vs the 300s default that killed a live 12-task dispatch) |
| Output dir | every task names its absolute output dir plus one example joined path -- else dispatches write to the home directory |
| Toolsets | `terminal` / `file` / `database` / `docker` dispatch cleanly; grant `browser` only after verifying it works |
| Parsing | every reply through the parse ladder (see sefi-orchestration); log the raw head/tail on failure |
