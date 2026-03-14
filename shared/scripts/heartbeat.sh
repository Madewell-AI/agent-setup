#!/usr/bin/env bash
# Heartbeat — Monitor background workers, detect completions, send notifications
# Run via cron every 15 minutes or as a systemd timer

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
ACTIVE_DIR="${AGENT_DIR}/workers/active"
COMPLETED_DIR="${AGENT_DIR}/workers/completed"
LOGS_DIR="${AGENT_DIR}/workers/logs"

mkdir -p "$ACTIVE_DIR" "$COMPLETED_DIR" "$LOGS_DIR"

# Optional: Slack notification function
# Set SLACK_WEBHOOK_URL or SLACK_BOT_TOKEN + SLACK_NOTIFICATION_CHANNEL in ~/.agent/.env
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

notify() {
    local message="$1"

    if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
        curl -s -X POST "https://slack.com/api/chat.postMessage" \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"channel\": \"${SLACK_NOTIFICATION_CHANNEL}\", \"text\": \"${message}\"}" \
            > /dev/null 2>&1 || true
    elif [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"${message}\"}" \
            > /dev/null 2>&1 || true
    fi
}

# Check each active worker
for meta_file in "$ACTIVE_DIR"/*.json; do
    [ -f "$meta_file" ] || continue

    WORKER_ID=$(python3 -c "import json; print(json.load(open('$meta_file'))['id'])")
    PID=$(python3 -c "import json; print(json.load(open('$meta_file')).get('pid', 'null'))")
    DESC=$(python3 -c "import json; print(json.load(open('$meta_file'))['description'])")
    LOG_FILE="${LOGS_DIR}/${WORKER_ID}.log"

    # Check if process is still running
    if [ "$PID" != "null" ] && [ "$PID" != "None" ] && ! kill -0 "$PID" 2>/dev/null; then
        # Process has ended — check result
        if [ -f "$LOG_FILE" ]; then
            # Check for completion markers
            if grep -q '\[DONE:' "$LOG_FILE"; then
                RESULT=$(grep '\[DONE:' "$LOG_FILE" | tail -1 | sed 's/.*\[DONE: //' | sed 's/\]//')
                notify "Worker completed: ${DESC} — ${RESULT}"
                echo "[$(date -Iseconds)] COMPLETED: ${WORKER_ID} — ${DESC} — ${RESULT}"
            elif grep -q '\[FAILED:' "$LOG_FILE"; then
                RESULT=$(grep '\[FAILED:' "$LOG_FILE" | tail -1 | sed 's/.*\[FAILED: //' | sed 's/\]//')
                notify "Worker FAILED: ${DESC} — ${RESULT}"
                echo "[$(date -Iseconds)] FAILED: ${WORKER_ID} — ${DESC} — ${RESULT}"
            else
                notify "Worker ended (no status marker): ${DESC}"
                echo "[$(date -Iseconds)] ENDED (no marker): ${WORKER_ID} — ${DESC}"
            fi
        fi

        # Move to completed
        mv "$meta_file" "$COMPLETED_DIR/"
        continue
    fi

    # Still running — check for status updates
    if [ -f "$LOG_FILE" ]; then
        LATEST_STATUS=$(grep '\[STATUS:' "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/.*\[STATUS: //' | sed 's/\]//' || echo "")
        if [ -n "$LATEST_STATUS" ]; then
            echo "[$(date -Iseconds)] RUNNING: ${WORKER_ID} — ${DESC} — ${LATEST_STATUS}"
        else
            echo "[$(date -Iseconds)] RUNNING: ${WORKER_ID} — ${DESC} — no status yet"
        fi
    fi
done

# Prune old completed workers (30+ days)
find "$COMPLETED_DIR" -name "*.json" -mtime +30 -delete 2>/dev/null || true
find "$LOGS_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
