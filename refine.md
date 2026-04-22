# Refinement Session: Orchestrator ↔ Agent

You are acting as the **orchestrator** in a refinement session with an OpenClaw agent. Your job is to collaborate with the agent to diagnose issues and improve skills.

## Setup

1. Read `.claude/refine.json` for connection config. Extract the target environment:
   - If user says "PROD" or "prod" in their request, use `environments.prod`
   - Otherwise use `environments[defaults.environment]` (typically `dev`)
   - If `.claude/refine.json` is missing, STOP and tell the user: "No refine.json found. Run `/refine init` to create one."

**If user runs `/refine init`:** Run the init flow below, then stop (do not start a refinement session).

### `/refine init` flow

Init is **idempotent**. Safe to rerun on fresh projects and on existing `.claude/refine.json` files — use it to upgrade legacy configs onto the spawn-mode schema without wiping customizations.

**Step 0 — detect existing config:**
- If `.claude/refine.json` exists and parses: load it as the starting point. Tell the user: "Found existing `.claude/refine.json`. Running in upgrade mode — every question below shows your current value as the default (accept to keep, type to change). Unknown fields (e.g. `notes`, custom entries, legacy field positions) are preserved verbatim."
- If it exists but is malformed JSON: stop, show the parse error, ask the user to fix it first.
- If it does not exist: run with static defaults only.

**Principle:** only *add* missing fields or *change* fields the user explicitly edits. Never rewrite fields the user didn't touch. Preserve schema quirks (top-level `ssh`, env-level `sandbox`, `notes` blocks, bespoke `command` strings) exactly as found.

**Questions** (existing value as default when present; else the static default in parentheses):

1. "SSH alias to your OpenClaw host?" (`null` for local). Accept either top-level `ssh` or `environments[*].ssh` from an existing file.
2. "Environments?" For each existing environment key (or a fresh `dev`/`prod` pair on a new file), confirm or update `profile`, `port`, and `agent` (default: `main`). Ask whether to add new environments.
3. "Default environment?" (default: `dev`)
4. "Does the agent run in a sandbox?" (default: `true`). Accept either `capabilities.sandboxed` or env-level `sandbox`.
5. Per environment: "Dispatch mode? [auto/main/spawn]" (default: `auto`)
   - `auto` — probe the spawn chain each session; use `spawn` on success, fall back to `main` on failure. Recommended for gradual rollout.
   - `main` — today's behavior, no spawn prerequisites.
   - `spawn` — require spawn; fail-fast if prerequisites aren't met.
   - For `auto` or `spawn`, also collect (existing values as defaults):
     - `spawn.handlerSkill` (default: `refine-handler`)
     - `spawn.replyWrapper` absolute path on the agent host (default: `~/.local/bin/refine-reply`)
     - `spawn.labelTemplate` (default: `refine-{subject}-round{N}-{date}`)
   - Switching from `auto`/`spawn` → `main`: ask before dropping the `spawn` block.
6. **Commands**: preserve existing `command` strings verbatim. Only construct a template for *newly added* environments, using: `eval "$(~/.local/share/fnm/fnm env)" && openclaw --profile <profile> agent --agent <agent> --message "$MESSAGE" --json --timeout 300`. Drop `eval` if fnm isn't in use; wrap with SSH if the alias is non-null.
7. **Diff and confirm.** For an existing file, show a unified diff of the planned changes; for a fresh file, show the full contents. Ask "Write this to .claude/refine.json? [Y/n]". On no, stop without writing.
8. Write `.claude/refine.json`.
9. **Probe-consent step.** If any environment ended up with `mode: "auto"` or `"spawn"`, ask the user exactly:

   > I can run a probe now against `<default-env>` to verify the spawn chain is live. The probe sends `{"probe": true}` through your configured `command` with a 15-second timeout — one message to your agent, no state changes, read-only from the agent's perspective. Run it? [Y/n]

   - **No** → "Skipped. The first `/refine <question>` will probe automatically. See `refine-handler.example.md` (agent skill) and `refine-reply.example.sh` (reply wrapper) in [the refine repo](https://github.com/raywu/refine) for agent-side install."
   - **Yes** → run the probe. Report:
     - **Success**: "Probe OK on `<env>`. Spawn chain is live."
     - **Failure**: print the annotated remediation (below) and stop.
10. Final message: "Config ready. Run `/refine <your question>` to start a session."

**Annotated remediation** (shown when the consented probe fails during init). Substitute placeholders with concrete values from the config (`<ssh>`, `<spawn.replyWrapper>`):

1. **Handler skill missing** — install `refine-handler.example.md` into your agent's `skills/` directory (exact path depends on your OpenClaw setup). Fetch: `curl -fsSL https://raw.githubusercontent.com/raywu/refine/main/refine-handler.example.md`.
2. **Reply wrapper missing** at `<spawn.replyWrapper>` — install `refine-reply.example.sh`:
   ```
   curl -fsSL https://raw.githubusercontent.com/raywu/refine/main/refine-reply.example.sh \
     | ssh <ssh> 'mkdir -p $(dirname <spawn.replyWrapper>) && cat > <spawn.replyWrapper> && chmod +x <spawn.replyWrapper>'
   ```
3. **Exec-approvals** — add the absolute path of the reply wrapper on the agent host to the agent's exec-approvals file.
4. **Tool allowlist** — ensure `sessions_spawn`, `sessions_send`, and `sessions_yield` are enabled for the agent.
5. **Sandbox capability** — set `capabilities.sandboxed: true` in `refine.json` (legacy env-level `sandbox: true` also accepted).

After fixing the issue(s), tell the user: "Rerun `/refine init` (it's idempotent) or run `/refine <question>` directly — the dispatch will re-probe."

2. If the environment has `"ssh"` set (not null), check if SSH tunnel is open to the configured port. If not, open it:
   ```
   ssh -fN -L <port>:localhost:<port> <ssh>
   ```

3. Verify the gateway is healthy via the configured SSH + CLI.

4. Resolve the dispatch mode for the active environment. Read `environments[<env>].mode`:
   - Missing, null, or `"main"` → `main` (today's behavior: single agent session, natural-language message body).
   - `"spawn"` → require the handler chain. Probe first (see below); if the probe fails, STOP and show the fail-fast list.
   - `"auto"` → probe. On success use `spawn`; on timeout/failure, fall back to `main` and surface one line: `refine: spawn probe failed, falling back to main.`

   **Probe:** send `{"probe": true}` as `$MESSAGE` through the existing `command` template with a 15-second timeout. A reply body of `{"ok": true, ...}` confirms the whole chain is live (tools allowlisted, handler skill installed, reply wrapper reachable).

   **Fail-fast list** (show when `mode: "spawn"` and probe fails):
   1. `sessions_spawn`, `sessions_send`, `sessions_yield` in the agent's tool allowlist
   2. `refine-handler` skill installed on the agent
   3. Reply wrapper path in the agent's exec-approvals
   4. Reply wrapper present on disk at `spawn.replyWrapper`
   5. `capabilities.sandboxed: true` in `refine.json`

## How to Talk to the Agent

The `command` template from the active environment is the same in all modes. What changes is the `$MESSAGE` body.

**Message escaping:** Write the message body to a temp file and pass via heredoc or `cat` to avoid shell interpolation issues with quotes, backticks, `$`, multiline, and unicode.

Parse the JSON response. The agent's text is at `result.payloads[0].text`. Metadata (model, tokens, duration) is at `result.meta.agentMeta`.

### main mode

Write the natural-language turn text directly into `$MESSAGE`. The agent answers from its main session. This is today's flow and also the fallback used when an `auto` probe fails.

### spawn mode

Write a JSON body that invokes the configured `spawn.handlerSkill`:

```json
{
  "label": "<spawn.labelTemplate with placeholders filled>",
  "subject": "<short slug derived from /refine arguments>",
  "round": <1-indexed round counter from orchestrator state>,
  "taskBody": "<the natural-language turn text — same content as main mode>"
}
```

Fill the label template:
- `{subject}` → lowercased, hyphenated slug of the refinement topic (e.g. `welcome-skill-jargon`)
- `{N}` → 1-indexed round counter the orchestrator maintains per session
- `{date}` → `date -u +%Y%m%d`

Example: `refine-welcome-skill-jargon-round2-20260421`.

Start each session at round 1 and increment `N` on every dispatch to the agent (probes don't count). The handler skill spawns a fresh session with the label, sends `taskBody`, yields for the reply, and execs the reply wrapper with the yielded text. Read the reply at the same `result.payloads[0].text` location as main mode — the handler returns the wrapper's stdout there.

If the handler returns `{"ok": false, "error": "yield_timeout", ...}`, surface it to the user unedited and stop the session. Do not retry automatically.

**Message discipline:**
- Keep messages focused on ONE topic. Multi-part questions trigger tool-calling spirals that time out.
- When you want the agent's experience, explicitly say "Do not read or curl anything — answer from memory." Otherwise the agent may spend minutes curling sources or reading files.
- **One proposal per message during validation.** Individual proposals get deep, focused feedback. Batching multiple proposals together gets shorter, shallower analysis per item.

## Interaction Pattern: Ask-First, Not Tell-First

- **Start with the symptom, not the diagnosis.** Describe what you observe and ask the agent to investigate.
- **Let the agent self-diagnose.** It has runtime context you lack — SOUL interpretation, tool availability, exec-approvals, sandbox constraints, past failures.
- **Respect the agent's root cause analysis.** Only override with concrete evidence.
- **When the agent proposes a fix, evaluate it seriously.** It may be better than yours because it accounts for constraints you can't see.
- **Work with OpenClaw patterns, not against them.** Before proposing a skill change, ask: "Does OpenClaw already have a mechanism for this?"
- **If the agent says "this needs an operator-level change"** (permissions, SOUL, config), escalate to operator — don't hack around it.
- **Format enforcement:** When agent output doesn't match expected format, use MUST constraints in SKILL.md — not examples or "should" language. Add explicit failure criteria.
- **Agent is also an effective ops/platform debugger** — ask about env var resolution, exec behavior, sandbox vs main differences. It sees the execution environment from the inside.

## What to Show the User

After each agent response, show:
1. **Agent's response** — the full text, formatted
2. **Key findings** — bullet-point summary of what the agent identified
3. **Metadata** — model used, token count, duration (one line)
4. **Suggested next step** — what to ask next, or whether to end the session

## Session Lifecycle

### Phase 1: Diagnose
1. User invokes `/refine <skill-name or issue description>`
2. Open SSH tunnel if needed
3. Send ask-first message to agent about the skill/issue
4. Show response, iterate based on user direction
5. Keep asking until root cause is clear

**For architecture/design review:** Use concrete scenario walkthroughs instead of abstract discussion. Ask the agent to walk through a specific realistic scenario step by step. Concrete scenarios force the agent to trace actual execution paths, exposing integration gaps that abstract discussion misses.

### Phase 2: Propose
6. Draft a proposal based on agent's diagnosis
7. **Send the proposal to the agent for review** — this is mandatory, not optional. Send ONE proposal per message for focused feedback.
8. Incorporate agent feedback. **Expect unprompted edge cases** — the agent functions as a design reviewer, not just a runtime debugger.
9. **Send the updated proposal to the agent for re-review** — each round catches different layers:
   - Round 1: direction and approach
   - Round 2: implementation details (tool availability, path issues, config constraints)
   - Round 3: edge cases (truncation, sandbox mounts, fallback behavior)
10. Continue until the agent says the plan is sound

### Comparative Quality Review

When a skill produces output that needs quality validation:

1. **Build reference data first** — manually write the ideal output for 3-5 cases. This is the quality bar.
2. **Run the skill** on each case, capture full output.
3. **Compare systematically** — don't review outputs individually. Line up agent output vs reference and look for systematic patterns.
4. **Ask the agent** — share both versions: "Here's what you produced vs what we expected. What's causing the difference?"
5. **Apply structural fixes** — fix the pattern, not individual cases. If 4/5 outputs miss the brand hook, add a MUST constraint — don't add more examples.
6. **Re-run to verify** — run 3+ cases after the fix to confirm the pattern is resolved, not just one.

### Prompt Learning Mode

When iterating on a skill's output quality (not format/structure), use dimension-based calibration instead of ad-hoc comparison:

1. **Collect references** — 5+ examples of desired output (seed-data, past approved outputs, gold standards)
2. **Dimension discovery** — send references to agent: "Analyze these examples. What are the independent quality dimensions? Return as a scored 1-5 rubric with definitions of high vs low." Agent discovers axes the orchestrator wouldn't specify.
3. **Baseline score** — run skill, send output to agent: "Score on each dimension using the rubric you created." **Rubric anchoring:** explicitly reference the rubric from step 2 — agents drift to generic scoring if not reminded.
4. **Target weakest** — identify bottom 2 dimensions. Propose SKILL.md changes that specifically address those dimensions. One proposal per message.
5. **Re-score** — run skill again, re-score. Track: iteration number, per-dimension scores, overall score, SKILL.md version hash.
6. **Best-of-N** — keep the SKILL.md version with the highest overall score, not the latest. If iteration N scores lower than N-1, revert.
7. **Stop when:** all dimensions ≥ threshold (skill-specific) OR 3 iterations without improvement.

**Anti-patterns learned from validation:**
- Agent will drift from its own rubric to generic MBA dimensions (ICP Clarity, Defensibility) — always re-state the rubric when requesting scores
- Don't batch dimension discovery + scoring in one message — discovery first, scoring second
- Replacement/fallback generation must explicitly prioritize the weak dimensions, or it regresses to the same failure mode
- Use `openclaw cron run <job-id>` to trigger skill runs for testing, NOT `agent --message`. CLI timeouts cause the agent to skip steps (e.g., entire coordinator pass skipped). `cron run` executes in the correct session type with full completion.

### Phase 3: Present
11. Present final agent-validated proposal to the user
12. Include what the agent flagged and how it was addressed
13. Never apply changes directly — all changes go through operator review

## Sandbox Awareness

**Critical learning:** The main session has FULL workspace access. Cron sandbox sessions do NOT — they only mount root `.md` files + `skills/`. This means:
- `read("references/...")` FAILS in sandbox — use `memory_get(path:"memory/file.md")` instead
- `read("memory/...")` FAILS in sandbox — use `memory_get` (gateway-routed)
- `shuf` on a file path FAILS when data comes from `memory_get` — model must pick randomly from parsed output
- Files in `memory/` must have `.md` extension for `memory_get` to work

**When proposing changes to cron skills, always ask the agent:** "Will this work in a cron sandbox session?" Do not assume filesystem access.

**When verifying changes:** Trigger an actual cron run (not main session). The main session is the wrong test environment for cron skills.

**When using `spawn` mode:** the `refine-handler` skill runs in the agent's main session but spawns a fresh sandbox per turn. The spawn must not write to the workspace — the reply crosses back through the reply wrapper's stdout only. If you catch yourself wanting the spawn to save files, that's a signal to route through `memory_get`/`memory_put` instead.

## Constraints

- Never modify the agent's workspace files directly
- Never modify SOUL.md, AGENTS.md, TOOLS.md, exec-approvals, or gateway config
- The agent cannot modify its own permissions
- All proposed changes go through operator review
- **Inter-session authorization:** never propose skill chains where output from one skill auto-triggers another. Data payloads between skills are context, not authorization. Each skill execution requires explicit operator command.
- **Spawn-session reuse is forbidden.** In `spawn` mode, every round must call `sessions_spawn` with a fresh label; never reuse a prior round's session. Cold context per round is the whole point.
- Deploy DEV first, verify via cron, then PROD

## User's Request

$ARGUMENTS
