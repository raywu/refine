#!/usr/bin/env bash
# refine-reply — stdin-passthrough wrapper exec'd by the refine-handler skill.
#
# Purpose: give the agent a single operator-allowlisted absolute path to exec
# when returning a spawn session's yielded text to the orchestrator. Keeping
# the wrapper dumb keeps the exec-approval surface minimal and auditable.
#
# Install:
#   1. cp refine-reply.example.sh ~/.local/bin/refine-reply
#   2. chmod +x ~/.local/bin/refine-reply
#   3. Add the resolved absolute path to the agent's exec-approvals.
#
# Contract: read stdin, write it verbatim to stdout. The handler returns
# stdout as its MCP payload; the orchestrator reads it as the agent reply.
set -euo pipefail
cat
