# /refine — Claude Code ↔ OpenClaw Agent Collaboration

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) slash command for iterative skill refinement with OpenClaw agents.

## What it does

`/refine` turns Claude Code into a provisioner that collaborates with your OpenClaw agent to diagnose issues, improve skills, and calibrate output quality. The agent self-diagnoses from runtime experience while Claude Code proposes and validates fixes.

**Includes:**
- **3-phase lifecycle:** Diagnose → Propose (mandatory agent review) → Present
- **Prompt Learning Mode:** Dimension-based quality calibration from reference examples
- **Comparative Quality Review:** Systematic output comparison against gold standards
- **Sandbox awareness:** Knows the difference between main and cron sandbox sessions
- **Ask-first interaction:** Start with symptoms, let the agent self-diagnose

## Setup

Save `refine.md` from this gist to `~/.claude/commands/refine.md`:

```bash
mkdir -p ~/.claude/commands
# Save refine.md from this gist to ~/.claude/commands/refine.md
```

Or tell your coding agent: "Save `refine.md` from this gist to `~/.claude/commands/refine.md`, then run `/refine init` in my project."

Then in your project:
1. Run `/refine init` — it walks you through creating `.claude/refine.json`
2. Start a session: `/refine why is my skill producing jargon-heavy output?`

Or create `.claude/refine.json` manually (see `refine.example.json`).

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
