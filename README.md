# /refine — Claude Code ↔ OpenClaw Agent Collaboration

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) slash command for iterative skill refinement with OpenClaw agents.

## What it does

`/refine` sets up an **agent-agent feedback loop** — Claude Code as the orchestrator, your OpenClaw agent as the runtime expert — to diagnose issues, improve skills, and calibrate output quality. The agent self-diagnoses from runtime experience while Claude Code proposes and validates fixes.

**Includes:**
- **3-phase lifecycle:** Diagnose → Propose (mandatory agent review) → Present
- **Prompt Learning Mode:** Dimension-based quality calibration from reference examples
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

For `spawn` mode (optional, see [Modes](#modes)):

- `sessions_spawn`, `sessions_send`, `sessions_yield` in the agent's tool allowlist
- The [`refine-handler`](./refine-handler.example.md) skill installed on the agent
- The [reply wrapper](./refine-reply.example.sh) at a fixed absolute path on the agent host
- That absolute path added to the agent's exec-approvals
- `capabilities.sandboxed: true` in `.claude/refine.json`

## Config schema

`.claude/refine.json` in your project root:

- `environments.{name}.ssh` — SSH alias to the agent's host (`null` for local)
- `environments.{name}.port` — gateway port
- `environments.{name}.mode` — `main` | `spawn` | `auto` (default: `main`). See [Modes](#modes).
- `environments.{name}.command` — full CLI template with `$MESSAGE` placeholder
- `environments.{name}.spawn.handlerSkill` — skill name the orchestrator invokes in spawn mode (default: `refine-handler`)
- `environments.{name}.spawn.replyWrapper` — absolute path to the reply wrapper on the agent host
- `environments.{name}.spawn.labelTemplate` — session-label pattern, supports `{subject}`, `{N}`, `{date}` placeholders
- `defaults.environment` — which env to use by default
- `capabilities.sandboxed` — whether cron runs in sandbox (affects guidance)

## Modes

`/refine` can route each refinement turn either into the agent's main session or into a fresh spawn session. Pick per environment.

| Mode | Behavior | When to pick |
| --- | --- | --- |
| `main` (default) | Sends the turn text directly to the agent's main session. One shared transcript. | Agents that don't have `sessions_spawn` yet, or when you want the simplest possible setup. This is the original `/refine` behavior. |
| `spawn` | Routes every turn through the `refine-handler` skill, which `sessions_spawn`s a fresh session per round and returns the reply via an operator-allowlisted wrapper script. | Agents with the prerequisites above. Gives context isolation (no pollution of the agent's main session), avoids lock contention with concurrent cron activity, and makes rounds reproducible (round N isn't biased by round N-1's memory). |
| `auto` | Probes the spawn chain at session start. Uses `spawn` if the probe succeeds; falls back to `main` with a one-line notice otherwise. | You plan to enable `spawn` but want graceful degradation if the handler chain isn't wired up yet. |

Omitting `mode` is treated as `main` so existing configs keep working unchanged.

Spawn-mode session labels follow `spawn.labelTemplate` (default `refine-{subject}-round{N}-{date}`), e.g. `refine-welcome-skill-jargon-round2-20260421`. Labels let you grep sandbox transcripts per round.

## Example session

```
/refine my onboarding skill is sending generic welcome messages instead of personalized ones
```

Claude Code sends the symptom to your agent, the agent self-diagnoses from runtime experience (e.g., "the personalization step reads from an empty user profile on first run"), and together they iterate on a fix with mandatory review rounds.

## Credits

Prompt Learning Mode is based on [Prompt Learning](https://gist.github.com/milstan/3b12f938f344f4ae1f511dd19e56adce) by [@milstan](https://github.com/milstan).

## License

[MIT](./LICENSE)
