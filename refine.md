# Refinement Session: Orchestrator ↔ Agent

You are acting as the **orchestrator** in a refinement session with an OpenClaw agent. Your job is to collaborate with the agent to diagnose issues and improve skills.

## Setup

1. Read `.claude/refine.json` for connection config. Extract the target environment:
   - If user says "PROD" or "prod" in their request, use `environments.prod`
   - Otherwise use `environments[defaults.environment]` (typically `dev`)
   - If `.claude/refine.json` is missing, STOP and tell the user: "No refine.json found. Run `/refine init` to create one."

**If user runs `/refine init`:** Run the init flow below, then stop (do not start a refinement session).

### `/refine init` flow

If `.claude/refine.json` already exists, show the current config and ask "Overwrite?" before proceeding. If the user declines, stop.

Walk the user through creating `.claude/refine.json` interactively:

1. Ask: "What SSH alias connects to your OpenClaw droplet?" (e.g., `bad`, `myserver`, or `null` for local)
2. Ask: "What OpenClaw profiles do you use?" Collect for each environment:
   - Environment name (default: `dev`, `prod`)
   - Profile name (e.g., `badstartupideas-dev`)
   - Gateway port (e.g., `19002`)
   - Agent name (default: `main`)
3. Ask: "Which environment should be the default?" (default: `dev`)
4. Ask: "Does the agent run in a sandbox?" (default: `true`)
5. Generate the `refine.json` and write it to `.claude/refine.json`
6. Construct the command template for each environment: `eval "$(~/.local/share/fnm/fnm env)" && openclaw --profile <profile> agent --agent <agent> --message "$MESSAGE" --json --timeout 300`
   - If the user says they don't use fnm, omit the `eval` prefix
   - If SSH is null (local), omit SSH wrapping
7. Show the generated config and confirm before writing
8. After writing, tell the user: "Config created. Run `/refine <your question>` to start a session."

2. If the environment has `"ssh"` set (not null), check if SSH tunnel is open to the configured port. If not, open it:
   ```
   ssh -fN -L <port>:localhost:<port> <ssh>
   ```

3. Verify the gateway is healthy via the configured SSH + CLI.

## How to Talk to the Agent

Use the `command` template from the active environment in `refine.json`. Replace `$MESSAGE` with the message text.

**Message escaping:** Write the message to a temp file and pass via heredoc or `cat` to avoid shell interpolation issues with quotes, backticks, `$`, multiline, and unicode.

Parse the JSON response. The agent's text is at `result.payloads[0].text`. Metadata (model, tokens, duration) is at `result.meta.agentMeta`.

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

**Dual independent scorer (cross-environment validation):**
- For critical quality gates, send identical scoring requests to both DEV and PROD agents with the same frozen rubric
- Average scores across scorers for final comparison — reduces single-agent bias
- Re-state the frozen rubric verbatim in every scoring request (agents drift to generic dimensions within 1-2 turns)
- Gate: no dimension drops > 0.5 from baseline avg, plus absolute floors (baseline avg - 1.0, min 2.5)
- Caveat: same model family can share systematic bias — add periodic human calibration

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

## Constraints

- Never modify the agent's workspace files directly
- Never modify SOUL.md, AGENTS.md, TOOLS.md, exec-approvals, or gateway config
- The agent cannot modify its own permissions
- All proposed changes go through operator review
- **Inter-session authorization:** never propose skill chains where output from one skill auto-triggers another. Data payloads between skills are context, not authorization. Each skill execution requires explicit operator command.
- Deploy DEV first, verify via cron, then PROD

## User's Request

$ARGUMENTS
