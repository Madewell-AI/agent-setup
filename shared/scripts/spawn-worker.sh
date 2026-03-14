#!/usr/bin/env bash
# Spawn Worker — Launch a background AI agent session for long-running tasks
# Usage: spawn-worker.sh "description" "prompt" [workdir]

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
WORKERS_DIR="${AGENT_DIR}/workers"
ACTIVE_DIR="${WORKERS_DIR}/active"
LOGS_DIR="${WORKERS_DIR}/logs"

mkdir -p "$ACTIVE_DIR" "$LOGS_DIR"

DESCRIPTION="${1:?Usage: spawn-worker.sh \"description\" \"prompt\" [workdir]}"
PROMPT="${2:?Usage: spawn-worker.sh \"description\" \"prompt\" [workdir]}"
WORKDIR="${3:-$HOME}"

# Generate worker ID
WORKER_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_FILE="${LOGS_DIR}/${WORKER_ID}.log"
META_FILE="${ACTIVE_DIR}/${WORKER_ID}.json"

# Detect which engine is available
if command -v claude &>/dev/null; then
    ENGINE="claude"
    ENGINE_CMD="claude -p --dangerously-skip-permissions --output-format text"
elif command -v codex &>/dev/null; then
    ENGINE="codex"
    ENGINE_CMD="codex --approval-mode full-auto"
else
    echo "ERROR: No AI engine found. Install Claude Code or Codex CLI."
    exit 1
fi

# Write worker metadata
cat > "$META_FILE" <<EOF
{
    "id": "${WORKER_ID}",
    "description": "${DESCRIPTION}",
    "engine": "${ENGINE}",
    "workdir": "${WORKDIR}",
    "pid": null,
    "started": "$(date -Iseconds)",
    "status": "starting"
}
EOF

# Inject worker instructions into the prompt
WORKER_PROMPT="You are running as a background worker. Your task: ${DESCRIPTION}

IMPORTANT: Write status markers to stdout as you work:
- [STATUS: brief description] — periodically, to show progress
- [DONE: brief summary] — when the task is complete
- [FAILED: reason] — if you cannot complete the task

Task details:
${PROMPT}"

# Write prompt to a temp file (avoids CLI argument length limits)
PROMPT_FILE=$(mktemp /tmp/worker-prompt-XXXXXX.md)
echo "$WORKER_PROMPT" > "$PROMPT_FILE"

# Spawn the worker as a detached process
(
    cd "$WORKDIR"
    # Unset CLAUDECODE to prevent nested session conflicts
    unset CLAUDECODE 2>/dev/null || true

    if [ "$ENGINE" = "claude" ]; then
        claude -p --dangerously-skip-permissions --output-format text < "$PROMPT_FILE" > "$LOG_FILE" 2>&1
    else
        codex --approval-mode full-auto "$(cat "$PROMPT_FILE")" > "$LOG_FILE" 2>&1
    fi

    rm -f "$PROMPT_FILE"
) &

WORKER_PID=$!

# Update metadata with PID
python3 -c "
import json
with open('${META_FILE}', 'r+') as f:
    data = json.load(f)
    data['pid'] = ${WORKER_PID}
    data['status'] = 'running'
    f.seek(0)
    json.dump(data, f, indent=2)
    f.truncate()
"

echo "Worker spawned: ${WORKER_ID} (PID: ${WORKER_PID})"
echo "Log: ${LOG_FILE}"
echo "Engine: ${ENGINE}"
