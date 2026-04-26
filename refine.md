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

   **Cross-check pre-flight** (always-on, silent when empty). Before dispatching anything to the agent, run two checks in parallel and surface findings only when relevant:

   - **Doc-baseline check.** If the user's request references a specific doc, file, or PR (`PR #135`, `consolidation plan`, an explicit path), run `git fetch && git log HEAD..origin/main -- <relevant paths>` for that scope. If origin is ahead on those paths, surface one line: "origin/main has N commits on `<path>` not in your local view — review or rebase before refining?" and pause for operator response. If no specific doc is named, skip silently.
   - **Sibling-memory grep.** Extract 3–5 key terms from the user's request (skill names, technical concepts, error symptoms). Grep `~/.claude/projects/*/memory/feedback_*.md` and `project_*.md` for matches. For each hit, surface one line: "Prior art in `<project>`: `<one-line description>`. Read before proceeding?" Operator chooses to read or skip per item.

   Both checks must complete before step 2. Silent when both return empty — operator only sees this step when there's something genuinely worth flagging.

2. Open SSH tunnel if needed
3. Send ask-first message to agent about the skill/issue
4. Show response, iterate based on user direction
5. Keep asking until root cause is clear

**For architecture/design review:** Use concrete scenario walkthroughs instead of abstract discussion. Ask the agent to walk through a specific realistic scenario step by step. Concrete scenarios force the agent to trace actual execution paths, exposing integration gaps that abstract discussion misses.

### Protocol auto-detection

After Phase 1 root cause is clear, evaluate whether Phase 2 should use the **R1-R4 design-comparison ladder** (Variant B of Prompt Learning Mode) instead of the default proposal-review flow. Detection signals — any one triggers:

- The user's `/refine` arguments enumerate alternatives ("A vs B", "either X or Y", "compare", "choose between", "should we do X or...").
- A plan-doc or design-doc in scope contains a `Paths considered`, `Alternatives`, or `Options` section.
- The agent's Phase 1 diagnosis enumerates 2+ approaches without converging on one.

When detected, ask once, in one line: "This looks like a design comparison. Engage the R1-R4 prompt-learning ladder (dimension discovery → score → recommend → artifact review)? [Y/n]". On yes, switch Phase 2 to the ladder. On no, stay on the default Phase 2 flow.

When **not** detected, stay on the default flow without prompting.

### Phase 2: Propose

If protocol auto-detection routed this session to Variant B (design comparison), follow the R1-R4 ladder in [Prompt Learning Mode → Variant B](#variant-b--design--path-comparison-r1-r4-ladder) instead of the default round structure below. R4's mandatory artifact review replaces "until the agent says the plan is sound."

Default Phase 2 (single-path proposal review):

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

### Prompt Learning Mode (skill output and design comparison)

Dimension-based calibration applies to two kinds of refinement, with shared core mechanics and variant-specific steps. Auto-detect (per "Protocol auto-detection" above) routes design-comparison sessions into Variant B; skill-output refinement uses Variant A.

**Core invariants (both variants):**

- **Frozen-rubric verbatim restatement is a MUST**, not a should. Every scoring round must repeat the rubric's dimensions and high-vs-low definitions exactly. This is the single load-bearing rule of the protocol — it stops the agent from drifting toward generic dimensions or its own prior-round preference. Skipping the verbatim restatement makes the protocol fail silently with confident-looking but biased scores.
- **Don't batch dimension discovery and scoring.** Discovery in one round, scoring in subsequent rounds. Batching pattern-matches the agent into generating both at once, which collapses into generic praise.
- **Single-scorer is the default.** Trigger dual-scorer (DEV+PROD agents, identical prompts, scores averaged per `feedback_quality_validation_dual_scorer.md`) when any of:
  - Score spread between top 2 paths/versions is ≤ 2 points
  - Operator weighting is contested
  - The change is load-bearing (acceptance gates, security boundaries, public APIs)

#### Variant A — Skill output quality

When iterating on a skill's output quality (not format/structure), use dimension-based calibration instead of ad-hoc comparison:

1. **Collect references** — 5+ examples of desired output (seed-data, past approved outputs, gold standards)
2. **Dimension discovery** — send references to agent: "Analyze these examples. What are the independent quality dimensions? Return as a scored 1-5 rubric with definitions of high vs low." Agent discovers axes the orchestrator wouldn't specify.
3. **Baseline score** — run skill, send output to agent: "Score on each dimension using the rubric you created." Restate the rubric verbatim per Core invariants.
4. **Target weakest** — identify bottom 2 dimensions. Propose SKILL.md changes that specifically address those dimensions. One proposal per message.
5. **Re-score** — run skill again, re-score. Track: iteration number, per-dimension scores, overall score, SKILL.md version hash.
6. **Best-of-N** — keep the SKILL.md version with the highest overall score, not the latest. If iteration N scores lower than N-1, revert.
7. **Stop when:** all dimensions ≥ threshold (skill-specific) OR 3 iterations without improvement.

#### Variant B — Design / path comparison (R1-R4 ladder)

When comparing 2+ design paths, alternatives, or architectures. Auto-detected per the protocol-auto-detection step above; can also be invoked explicitly when you have a known multi-option decision.

1. **R1 — Dimension discovery only.** Send the problem context and candidate paths (one paragraph each). Ask: "Discover 5–7 independent quality dimensions for this comparison. For each, define what 1, 3, and 5 look like. Do not score yet." Agent returns the rubric.
2. **R2 — Score N paths.** Restate the R1 rubric verbatim. Send: "Score paths A, B, C on each dimension using the rubric below. Half-points allowed. Return as a strict markdown table: dimension | A | B | C | confidence | notes." No prose; just the table. The strict format prevents drift back to discursive analysis.
3. **R3 — Recommend + tensions + low-confidence probes.** Restate the R1 rubric verbatim again. Send: "Given your R2 scores, recommend a path. Identify the dimensions where the recommendation depends most on operator weighting (tension surface). Identify the lowest-confidence scores and propose what evidence would raise confidence."
4. **R4 — Concrete artifact review (mandatory before declaring SOUND).** Draft the actual artifact the recommendation produces — SQL, code change, config diff, full plan section. Send to the agent: "Review this concrete artifact against your R3 recommendation. Where does the artifact diverge from architectural intent? What concrete bugs do you see?" R4 routinely catches what abstract R1-R3 misses — in the mark-bot validation session, R1-R3 abstract scored Path C transition friction at 5; R4 review of the ~110-line SQL caught 5 concrete bugs (RLS gap, missing role-membership grants, type-cast errors, weak `IS NOT NULL` policy, USING clause needing `decided_by IS NULL`).

**Stop when:** R4 surfaces no blocking concrete bugs AND the operator accepts the recommendation given the surfaced tensions. Single-scorer is sufficient when the score spread is decisive; escalate to dual-scorer per Core invariants when close.

#### Dual independent scorer (for critical quality gates)

*Dependencies (check before running — if any are missing, stop and ask the user):*

1. A **frozen scoring rubric** — typically the one produced by Prompt Learning Mode's dimension discovery (Variant A step 2 or Variant B R1). If no rubric exists, run dimension discovery first, or ask the user to supply one. Do not invent a rubric inside a scoring request.
2. **Pre- and post-change outputs** to score. Any source works (live skill runs, saved fixtures, pasted text) — dual-scorer does not assume any harness, log file, or repo layout.
3. **Two scorer endpoints.** Ideally `environments.dev` and `environments.prod` from `refine.json`; if only one environment (or one model) is available, see "The two scorer instances" below for the tiered fallback ladder — do not silently degrade to same-model-twice.

*When to run:* the user says "dual-scorer", "PROD gate", "validate before shipping", or similar; OR the current session is validating a Prompt Learning Mode change about to be merged/shipped; OR the Core-invariants threshold fires (top-2 score spread ≤ 2, contested weighting, or load-bearing change). Skip for exploratory iteration, format/structure-only changes, and typo fixes.

*The two scorer instances — pick the strongest tier available.* Walk the list top-down and stop at the first tier the user's config supports. State which tier you used and what it does/doesn't catch, so the user knows how much weight to give the result.

1. **Two distinct environments** (`environments.dev` + `environments.prod` in `refine.json`, preferably backed by different models or model versions) — full protocol; catches both systematic bias and sampling noise.
2. **Same environment, two commands pinned to different model versions** — e.g. a second `command` template in the same environment that pins a different model than the primary. Catches family-level bias but not cross-provider bias. Use when the user has only one host configured but multiple models available on it.
3. **Same environment, two sessions with the same model** — only catches sampling noise, not bias. Use only when the user has no way to vary the model; report clearly that systematic-bias coverage is unavailable.
4. **Single scorer + human spot-check** — run the single-scorer flow, then ask the user to eyeball the 1–2 dimensions they care about most. Acceptable when the change is small or the user explicitly accepts reduced coverage.
5. **Skip dual-scorer** — fall back to Prompt Learning Mode's single-scorer flow with an explicit warning that the critical-gate protocol couldn't be met. Appropriate when none of the above are available and the user is willing to proceed without the gate.

If you fall back to tier 3 or weaker, ask the user before proceeding: a weak dual-scorer result can read as a strong signal if the tier isn't disclosed.

*Protocol:*
- Send identical scoring requests to both scorer instances using the same frozen rubric (the rubric produced by dimension discovery in Variant A step 2 or Variant B R1).
- Average scores across scorers for each dimension — reduces single-scorer bias.
- Re-state the frozen rubric verbatim in every scoring request (per Core invariants — scorers drift to generic dimensions within 1-2 turns otherwise).
- Regression gate (heuristic — tune per skill): no dimension drops more than ~0.5 from baseline average, plus absolute floors (e.g. baseline avg − 1.0, with a minimum of 2.5). If scorers disagree on direction (one says win, other says regression), treat as FAIL until the discrepancy is resolved.
- Caveat: scorers from the same model family can share systematic bias — add periodic human calibration to catch blind spots.

*Output:* present a single table with columns `Dimension | Run A (pre) avg | Run B (post) avg | Δ` (cells already averaged across scorers), a PASS/FAIL verdict, and a one-line note on whether the biggest deltas land on the targeted dimensions.

#### Anti-patterns

- Agent drifts to generic dimensions (ICP Clarity, Defensibility, "Robustness") when not re-anchored — verbatim restatement (per Core invariants) is the fix.
- Replacement/fallback generation must explicitly prioritize the weak dimensions in Variant A, or it regresses to the same failure mode.
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
