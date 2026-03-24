#!/usr/bin/env bash
# Spawn Worker — Launch a background AI agent session for long-running tasks
# Usage: spawn-worker.sh "description" "prompt" [workdir]

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
WORKERS_DIR="${AGENT_DIR}/workers"
ACTIVE_DIR="${WORKERS_DIR}/active"
LOGS_DIR="${WORKERS_DIR}/logs"

mkdir -p "$ACTIVE_DIR" "$LOGS_DIR"

DESCRIPTION="${1:-}"
PROMPT="${2:-}"
WORKDIR="${3:-$HOME}"

if [[ -z "$DESCRIPTION" || -z "$PROMPT" ]]; then
  echo "Usage: spawn-worker.sh <description> <prompt> [workdir]" >&2
  exit 1
fi

# Generate worker ID
WORKER_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_FILE="${LOGS_DIR}/${WORKER_ID}.log"
META_FILE="${ACTIVE_DIR}/${WORKER_ID}.json"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Detect which engine is available
if command -v claude &>/dev/null; then
    ENGINE="claude"
elif command -v codex &>/dev/null; then
    ENGINE="codex"
else
    echo "ERROR: No AI engine found. Install Claude Code or Codex CLI."
    exit 1
fi

# Append worker instructions to the prompt
FULL_PROMPT="${PROMPT}

---
Background worker instructions: Periodically write [STATUS: brief description of current step] lines to stdout so the heartbeat monitor can track your progress. Write [DONE: brief summary of what was accomplished] when complete. Write [FAILED: reason] if you cannot complete the task."

# Spawn the worker as a detached process
(
    cd "$WORKDIR"
    # Unset agent session markers to prevent nested-session conflicts
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true

    if [ "$ENGINE" = "claude" ]; then
        claude -p --dangerously-skip-permissions --output-format text -- "$FULL_PROMPT" > "$LOG_FILE" 2>&1
    else
        codex --approval-mode full-auto "$FULL_PROMPT" > "$LOG_FILE" 2>&1
    fi
) &

WORKER_PID=$!

# Write worker metadata
cat > "$META_FILE" <<EOF
{
  "id": "${WORKER_ID}",
  "description": "${DESCRIPTION}",
  "engine": "${ENGINE}",
  "workdir": "${WORKDIR}",
  "pid": ${WORKER_PID},
  "log_file": "${LOG_FILE}",
  "started_at": "${STARTED_AT}",
  "last_update": "${STARTED_AT}",
  "last_status": "starting...",
  "status": "running"
}
EOF

echo "Worker spawned: ${WORKER_ID}"
echo "PID: ${WORKER_PID}"
echo "Description: ${DESCRIPTION}"
echo "Log: ${LOG_FILE}"
echo "Engine: ${ENGINE}"
