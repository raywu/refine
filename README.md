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
- **Skill bundle (preview):** Skill-format version staged at `skills/refine/` for early testing — auto-discovery, bundled example.json, `evals/` subdir for prompt-learning artifacts. See [Skill bundle (preview)](#skill-bundle-preview)

## Setup

> **Skill preview available.** A Skill-format version of `/refine` is staged at [`skills/refine/`](skills/refine/) for early testing. It is not yet the recommended install path; the slash-command install below remains canonical until v1.0. To preview, see [Skill bundle (preview)](#skill-bundle-preview) below.

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

## Skill bundle (preview)

A Claude Code Skill version of `/refine` is staged at `skills/refine/`:

```
skills/refine/
├── SKILL.md              # the prompt + YAML frontmatter (name + description)
├── refine.example.json   # bundled config template
├── LICENSE
└── evals/                # placeholder for prompt-learning rubrics, gold/foil sets
```

**What changes vs the slash command:**
- Skills support **auto-discovery** — Claude can offer `/refine` when you describe a matching symptom in plain conversation, without typing the slash. Explicit `/refine <symptom>` still works identically.
- Bundled resources (example config, future rubrics) ship alongside the prompt.
- Distribution becomes directory-based instead of single-file.

**Try it (manual symlink, reversible):**

```bash
ln -s "$(pwd)/skills/refine" ~/.claude/skills/refine
```

This adds the skill alongside the existing `~/.claude/commands/refine.md`. Claude Code's resolution behavior in this coexistence state has not yet been verified — surface unexpected results before relying on the skill version. Remove with `rm ~/.claude/skills/refine`.

**Roadmap:**
- v1.0 will make the skill canonical and deprecate the slash-command path.
- v0.x will be tagged so the slash-command install remains fetchable for rollback.
- Migration for existing users is one of:
  - **Direct curl users**: `rm ~/.claude/commands/refine.md && git clone https://github.com/raywu/refine ~/.claude/skills/refine` (final clone shape pending v1.0).
  - **Dotfiles users**: a single dotfiles PR replacing the `claude/commands/refine.md` symlink with a `claude/skills/refine/` directory symlink.

## Credits

Prompt Learning Mode is based on [Prompt Learning](https://gist.github.com/milstan/3b12f938f344f4ae1f511dd19e56adce) by [@milstan](https://github.com/milstan).

## License

[MIT](./LICENSE)
