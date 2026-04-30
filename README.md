# /refine — Orchestrator ↔ OpenClaw Agent Collaboration

A portable Skill for iterative skill refinement with [OpenClaw](https://openclaw.ai) agents. Works with both [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://developers.openai.com/codex) — the same `SKILL.md` is loaded by either tool's native skill registry.

## What it does

`/refine` sets up an **orchestrator-agent feedback loop** — your CLI tool (Claude Code or Codex) as the orchestrator, your OpenClaw agent as the runtime expert — to diagnose issues, improve skills, and calibrate output quality. The agent self-diagnoses from runtime experience while the orchestrator proposes and validates fixes.

**Includes:**
- **3-phase lifecycle:** Diagnose → Propose (mandatory agent review) → Present
- **Cross-check pre-flight:** always-on, silent-when-empty doc-baseline + sibling-memory check before each session
- **Protocol auto-detection:** detects multi-path design comparison and offers the R1-R4 ladder; otherwise stays on the default flow
- **Prompt Learning Mode (skill output and design comparison):** frozen-rubric scoring with mandatory artifact review
- **Dual independent scorer:** Runs identical scoring requests across your `dev` and `prod` environments to catch single-scorer bias before a production gate. Requires a frozen scoring rubric (typically produced by Prompt Learning Mode's dimension discovery) plus pre/post outputs to score — no harness log, CI, or repo layout assumptions
- **Comparative Quality Review:** Systematic output comparison against gold standards
- **Sandbox awareness:** Knows the difference between main and cron sandbox sessions
- **Ask-first interaction:** Start with symptoms, let the agent self-diagnose
- **Auto-discovery:** the orchestrator can offer `/refine` proactively when you describe a matching symptom in plain conversation; explicit `/refine <symptom>` always works too

## Setup

The repo IS the skill bundle — the same directory clones cleanly into either tool's skill registry.

### Claude Code

```bash
git clone https://github.com/raywu/refine ~/.claude/skills/refine
```

Upgrade later:

```bash
git -C ~/.claude/skills/refine pull
```

### Codex CLI

```bash
git clone https://github.com/raywu/refine ~/.codex/skills/refine
```

Upgrade later:

```bash
git -C ~/.codex/skills/refine pull
```

Restart Codex after install so it picks up the new skill (per Codex's skill-installer convention).

### Both tools on one machine

Run both commands. They install into separate paths and don't interfere — each tool's skill registry resolves independently. The two installs share no state at runtime; upgrades are independent (`git pull` each).

If you maintain a dotfiles repo, the typical pattern is to put both `git clone`/`git pull` blocks into `install.sh` so a single run keeps both up to date.

### Per-project config

After installing the skill (one tool or both), each project that uses refine needs a `.claude/refine.json` (the path is currently `.claude/`-prefixed regardless of which tool you run; the directory name is just a string and Codex doesn't care). Create it via **either**:

**Interactive (recommended):**
```
/refine init
```
Walks you through the config and writes it.

**Manual:**
```bash
mkdir -p .claude
cp ~/.claude/skills/refine/refine.example.json .claude/refine.json   # Claude Code
# or
cp ~/.codex/skills/refine/refine.example.json .claude/refine.json    # Codex CLI
# edit .claude/refine.json to match your environment
```

Once configured, start a session:
```
/refine why is my skill producing jargon-heavy output?
```

### Why `git clone` (and not `ln -s`)

Both tools have known symlink-handling bugs in current releases:

- **Claude Code 2.1.x** registers symlinked skills 3–6 times in the slash menu ([#23819](https://github.com/anthropics/claude-code/issues/23819), [#24140](https://github.com/anthropics/claude-code/issues/24140), [#37590](https://github.com/anthropics/claude-code/issues/37590)).
- **Codex CLI** silently skips symlinked `SKILL.md` and symlinked skill directories ([#17344](https://github.com/openai/codex/issues/17344), [#8943](https://github.com/openai/codex/issues/8943), [#11314](https://github.com/openai/codex/issues/11314), [#9898](https://github.com/openai/codex/issues/9898)).

Different failure modes, same operational answer: install as a real directory copy via `git clone`. Until both upstreams resolve their symlink bugs, the install path must be a real directory.

## Upgrading from v0.x

Earlier versions installed `/refine` as a Claude Code slash command at `~/.claude/commands/refine.md`. To upgrade:

```bash
rm ~/.claude/commands/refine.md
git clone https://github.com/raywu/refine ~/.claude/skills/refine
```

That's it. Your per-project `.claude/refine.json` is unchanged — schema is identical.

If you maintain a dotfiles repo that installs `~/.claude/commands/refine.md` via symlink, swap that for a `git clone`/`pull` of this repo into `~/.claude/skills/refine`.

## Rollback to v0.x

If the Skill conversion breaks something subtle and you need the slash-command shape back (Claude Code only — v0.x predates Codex support):

```bash
rm -rf ~/.claude/skills/refine
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/raywu/refine/v0.x/refine.md \
  -o ~/.claude/commands/refine.md
```

The `v0.x` git tag preserves the last commit where `refine.md` lived at the repo root.

## Requirements

- One of:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI or IDE extension (2.1.x or later), or
  - [Codex CLI](https://developers.openai.com/codex) with skill support
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

The orchestrator sends the symptom to your agent, the agent self-diagnoses from runtime experience (e.g., "the personalization step reads from an empty user profile on first run"), and together they iterate on a fix with mandatory review rounds.

## Known limitations

- **No `argument-hint` autocomplete affordance.** As a Skill, `/refine` doesn't yet show the inline argument hint that the v0.x slash command had. Awaiting upstream support for skill-level hints in either Claude Code or Codex.
- **Symlink installs broken in both tools.** See "Why `git clone` (and not `ln -s`)" above. Track upstream issues for resolution.

## Credits

Prompt Learning Mode is based on [Prompt Learning](https://gist.github.com/milstan/3b12f938f344f4ae1f511dd19e56adce) by [@milstan](https://github.com/milstan).

## License

[MIT](./LICENSE)
