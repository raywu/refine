# /refine — Claude Code ↔ OpenClaw Agent Collaboration

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) slash command for iterative skill refinement with OpenClaw agents.

## What it does

`/refine` sets up an **agent-agent feedback loop** — Claude Code as the orchestrator, your OpenClaw agent as the runtime expert — to diagnose issues, improve skills, and calibrate output quality. The agent self-diagnoses from runtime experience while Claude Code proposes and validates fixes.

**Includes:**
- **3-phase lifecycle:** Diagnose → Propose (mandatory agent review) → Present
- **Cross-check pre-flight:** always-on, silent-when-empty doc-baseline + sibling-memory check before each session
- **Protocol auto-detection:** detects multi-path design comparison and offers the R1-R4 ladder; otherwise stays on the default flow
- **Prompt Learning Mode (skill output and design comparison):** frozen-rubric scoring with mandatory artifact review
- **Dual independent scorer:** Runs identical scoring requests across your `dev` and `prod` environments to catch single-scorer bias before a production gate. Requires a frozen scoring rubric (typically produced by Prompt Learning Mode's dimension discovery) plus pre/post outputs to score — no harness log, CI, or repo layout assumptions
- **Comparative Quality Review:** Systematic output comparison against gold standards
- **Sandbox awareness:** Knows the difference between main and cron sandbox sessions
- **Ask-first interaction:** Start with symptoms, let the agent self-diagnose

## Setup

Install the slash command:

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/raywu/refine/main/refine.md \
  -o ~/.claude/commands/refine.md
```

Or tell your coding agent: "Install `refine.md` from https://github.com/raywu/refine to `~/.claude/commands/refine.md`, then run `/refine init` in my project."

Then in your project, create `.claude/refine.json` via **either**:

**Interactive (recommended):**
```
/refine init
```
Walks you through the config and writes it.

**Manual:**
```bash
mkdir -p .claude
curl -fsSL https://raw.githubusercontent.com/raywu/refine/main/refine.example.json \
  -o .claude/refine.json
# edit .claude/refine.json to match your environment
```

Once configured, start a session:
```
/refine why is my skill producing jargon-heavy output?
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI or IDE extension
- An [OpenClaw](https://openclaw.ai) agent accessible via SSH or locally
- The `openclaw` CLI installed on the agent's host

## Config schema

`.claude/refine.json` in your project root:

- `environments.{name}.ssh` — SSH alias to the agent's host (`null` for local)
- `environments.{name}.port` — gateway port
- `environments.{name}.command` — full CLI template with `$MESSAGE` placeholder
- `defaults.environment` — which env to use by default
- `capabilities.sandboxed` — whether cron runs in sandbox (affects guidance)

## Example session

```
/refine my onboarding skill is sending generic welcome messages instead of personalized ones
```

Claude Code sends the symptom to your agent, the agent self-diagnoses from runtime experience (e.g., "the personalization step reads from an empty user profile on first run"), and together they iterate on a fix with mandatory review rounds.

## Credits

Prompt Learning Mode is based on [Prompt Learning](https://gist.github.com/milstan/3b12f938f344f4ae1f511dd19e56adce) by [@milstan](https://github.com/milstan).

## License

[MIT](./LICENSE)
