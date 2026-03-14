#!/usr/bin/env bash
# Run Job — Execute a single cron job by ID
# Called by systemd timers or manually via manage.sh run <id>

set -euo pipefail

CRON_DIR="${HOME}/.agent/cron"
JOBS_FILE="${CRON_DIR}/jobs.json"
LOGS_DIR="${CRON_DIR}/logs"
AGENT_DIR="${HOME}/.agent"

JOB_ID="${1:?Usage: run-job.sh <job-id>}"

# Load env
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

# Read job config
JOB_CONFIG=$(python3 -c "
import json, sys
with open('${JOBS_FILE}') as f:
    jobs = json.load(f)
for j in jobs:
    if j['id'] == '${JOB_ID}':
        json.dump(j, sys.stdout)
        sys.exit(0)
print('null')
sys.exit(1)
")

if [ "$JOB_CONFIG" = "null" ]; then
    echo "Job not found: ${JOB_ID}"
    exit 1
fi

# Parse job fields
PROMPT=$(echo "$JOB_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['prompt'])")
WORKDIR=$(echo "$JOB_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('workdir', '$HOME'))")
DELIVER=$(echo "$JOB_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('deliver', False))")
JOB_NAME=$(echo "$JOB_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")

# Expand ~ in workdir
WORKDIR="${WORKDIR/#\~/$HOME}"

# Setup logging
JOB_LOG_DIR="${LOGS_DIR}/${JOB_ID}"
mkdir -p "$JOB_LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${JOB_LOG_DIR}/${TIMESTAMP}.log"
RUNS_LOG="${JOB_LOG_DIR}/runs.jsonl"

echo "[$(date -Iseconds)] Starting job: ${JOB_NAME}" | tee "$LOG_FILE"

# Detect engine
if command -v claude &>/dev/null; then
    ENGINE="claude"
elif command -v codex &>/dev/null; then
    ENGINE="codex"
else
    echo "ERROR: No AI engine found" | tee -a "$LOG_FILE"
    exit 1
fi

# Run the job
START_TIME=$(date +%s)

if [ "$ENGINE" = "claude" ]; then
    OUTPUT=$(cd "$WORKDIR" && echo "$PROMPT" | claude -p --dangerously-skip-permissions --output-format text 2>&1) || true
else
    OUTPUT=$(cd "$WORKDIR" && codex --approval-mode full-auto "$PROMPT" 2>&1) || true
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "$OUTPUT" >> "$LOG_FILE"
echo "[$(date -Iseconds)] Completed in ${DURATION}s" >> "$LOG_FILE"

# Log run metadata
echo "{\"job_id\": \"${JOB_ID}\", \"timestamp\": \"$(date -Iseconds)\", \"duration_s\": ${DURATION}, \"engine\": \"${ENGINE}\"}" >> "$RUNS_LOG"

# Deliver output to Slack if configured
if [ "$DELIVER" = "True" ] || [ "$DELIVER" = "true" ]; then
    # Truncate to 3000 chars for Slack
    TRUNCATED=$(echo "$OUTPUT" | head -c 3000)

    if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
        # Escape JSON special chars
        ESCAPED=$(echo "$TRUNCATED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" | sed 's/^"//;s/"$//')

        curl -s -X POST "https://slack.com/api/chat.postMessage" \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"channel\": \"${SLACK_NOTIFICATION_CHANNEL}\", \"text\": \"${ESCAPED}\"}" \
            > /dev/null 2>&1 || true
    fi
fi

# Prune old logs (keep last 30 days)
find "$JOB_LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
