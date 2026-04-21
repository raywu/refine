# refine-handler — Agent-side handler for orchestrator-driven refinement

This is a reference SKILL.md for your **OpenClaw agent**. Install it in your agent's `skills/` directory as `refine-handler.md`. It pairs with the `/refine` orchestrator slash command on the Claude Code side.

## Purpose

When `/refine` runs in `spawn` mode, each refinement turn is routed to this skill rather than executed in the agent's main session. The skill spawns a fresh subagent session per turn so that main-session memory, lock-contention, and prior-round bias don't leak into refinement.

## Prerequisites

- `sessions_spawn`, `sessions_send`, `sessions_yield` in the agent's tool allowlist.
- The reply wrapper installed at the path the orchestrator was configured with (e.g. `~/.local/bin/refine-reply`) and present in the agent's exec-approvals with its absolute path.
- Sandbox-safe operation: this skill MUST NOT write to the agent workspace. Replies return through the MCP payload only.

## Message shapes

The orchestrator sends one of two JSON bodies.

### 1. Probe

```json
{ "probe": true }
```

Respond without spawning. Reply body:

```json
{ "ok": true, "tools": ["sessions_spawn", "sessions_send", "sessions_yield"] }
```

The orchestrator uses the probe reply as a liveness check covering the whole chain (skill installed + tools allowlisted + reply wrapper reachable). If this probe fails, the orchestrator falls back to `main` mode (when configured `auto`) or stops with a fail-fast error (when configured `spawn`).

### 2. Dispatch

```json
{
  "label": "refine-<subject-slug>-round<N>-<YYYYMMDD>",
  "subject": "<short topic>",
  "round": 1,
  "taskBody": "<the orchestrator's turn text>"
}
```

Handle it in this order:

1. `sessions_spawn` with `label` from the payload. Do not reuse an existing session — each round starts cold by design.
2. `sessions_send` the `taskBody` verbatim into the spawned session.
3. `sessions_yield` and wait for the spawn to complete its turn.
4. Exec the reply wrapper (absolute path from exec-approvals) with the yielded text on stdin. Do not transform or summarize.
5. Return the wrapper's stdout as the MCP payload. No workspace writes.

## Constraints

- **Never** read or write files in the agent workspace from inside this skill. All data crosses through the message body and the reply wrapper's stdin/stdout.
- **Never** reuse a spawn session across rounds — the orchestrator expects round N to be uncontaminated by round N-1.
- If `sessions_yield` times out, return a JSON error body: `{ "ok": false, "error": "yield_timeout", "label": "<label>" }`. The orchestrator will surface this to the user without retrying.
- Labels are opaque to this skill; do not parse or rewrite them.
