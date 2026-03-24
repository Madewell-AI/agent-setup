#!/usr/bin/env bash
# Run Job — Execute a single cron job by ID
# Called by systemd timers or manually via manage.sh run <id>

set -euo pipefail

JOB_ID="${1:-}"
if [[ -z "$JOB_ID" ]]; then
    echo "Usage: run-job.sh <job-id>" >&2
    exit 1
fi

CRON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_FILE="${CRON_DIR}/jobs.json"
AGENT_DIR="${HOME}/.agent"
LOG_DIR="${CRON_DIR}/logs/${JOB_ID}"
mkdir -p "$LOG_DIR"

# Load env
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

# Read job config — supports both flat array and {jobs: [...]} format
JOB_CONFIG=$(python3 -c "
import json, sys
data = json.load(open('${JOBS_FILE}'))
jobs = data.get('jobs', data) if isinstance(data, dict) else data
match = next((j for j in jobs if j['id'] == '${JOB_ID}'), None)
if not match:
    print('NOT_FOUND', end='')
    sys.exit(1)
print(json.dumps(match))
")

if [[ "$JOB_CONFIG" == "NOT_FOUND" ]]; then
    echo "Job '${JOB_ID}' not found in jobs.json" >&2
    exit 1
fi

# Check if job is enabled
ENABLED=$(echo "$JOB_CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('enabled', True))")
if [[ "$ENABLED" == "False" ]]; then
    echo "Job '${JOB_ID}' is disabled, skipping." >&2
    exit 0
fi

# Parse job fields
PROMPT=$(echo "$JOB_CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['prompt'])")
WORKDIR=$(echo "$JOB_CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('workdir', '$HOME'))")
DELIVER=$(echo "$JOB_CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('deliver', False))")
JOB_NAME=$(echo "$JOB_CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['name'])")

# Expand ~ in workdir
WORKDIR="${WORKDIR/#\~/$HOME}"

# Setup logging
RUN_TS=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
LOG_FILE="${LOG_DIR}/${RUN_TS}.log"
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=== Agent cron run ===" | tee "$LOG_FILE"
echo "Job:     ${JOB_ID} (${JOB_NAME})" | tee -a "$LOG_FILE"
echo "Started: ${STARTED_AT}" | tee -a "$LOG_FILE"
echo "---" | tee -a "$LOG_FILE"

# Detect engine
if command -v claude &>/dev/null; then
    ENGINE="claude"
elif command -v codex &>/dev/null; then
    ENGINE="codex"
else
    echo "ERROR: No AI engine found" | tee -a "$LOG_FILE"
    exit 1
fi

# When delivering to Slack, append formatting rules so the agent outputs Slack-compatible text
FULL_PROMPT="$PROMPT"
if [[ "$DELIVER" == "True" || "$DELIVER" == "true" ]]; then
    FULL_PROMPT="$PROMPT

--- Slack Formatting Rules (ALWAYS follow these) ---
Your response will be posted directly to Slack. Slack uses mrkdwn, NOT standard markdown.
- Use *bold* for emphasis (not **bold**)
- Use _italic_ for italics (not *italic*)
- Use \`inline code\` for code snippets
- Use \`\`\`code blocks\`\`\` for multi-line code
- Bullet lists: use - or • at the start of lines
- NEVER use markdown tables (| col | col | format). Slack does not render them and they look broken. Always use labeled lines or bullet lists instead. This is a hard rule — no exceptions.
- NO # headers — use *bold text* as section labels instead
- NO HTML tags
- Keep responses concise — this is a chat interface"
fi

# Run the job
# Unset CLAUDECODE so nested sessions work when triggered from within an agent session
unset CLAUDECODE 2>/dev/null || true
STATUS="ok"
OUTPUT=""

if [ "$ENGINE" = "claude" ]; then
    if OUTPUT=$(cd "$WORKDIR" && claude -p "$FULL_PROMPT" --output-format text --dangerously-skip-permissions 2>>"$LOG_FILE"); then
        echo "$OUTPUT" | tee -a "$LOG_FILE"
    else
        STATUS="error"
        echo "[ERROR] claude exited non-zero" | tee -a "$LOG_FILE"
    fi
else
    if OUTPUT=$(cd "$WORKDIR" && codex --approval-mode full-auto "$FULL_PROMPT" 2>>"$LOG_FILE"); then
        echo "$OUTPUT" | tee -a "$LOG_FILE"
    else
        STATUS="error"
        echo "[ERROR] codex exited non-zero" | tee -a "$LOG_FILE"
    fi
fi

FINISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "---" | tee -a "$LOG_FILE"
echo "Finished: ${FINISHED_AT}" | tee -a "$LOG_FILE"
echo "Status:   ${STATUS}" | tee -a "$LOG_FILE"

# Write structured run metadata
python3 - <<PYEOF >> "${LOG_DIR}/runs.jsonl"
import json
record = {
    "ts": "${RUN_TS}",
    "jobId": "${JOB_ID}",
    "name": "${JOB_NAME}",
    "status": "${STATUS}",
    "startedAt": "${STARTED_AT}",
    "finishedAt": "${FINISHED_AT}",
    "logFile": "${LOG_FILE}"
}
print(json.dumps(record))
PYEOF

# Deliver output to Slack if configured
if [[ "$DELIVER" == "True" || "$DELIVER" == "true" ]]; then
    # Truncate output for Slack (3000 char limit)
    SUMMARY="[Agent cron] ${JOB_NAME}
Status: ${STATUS}

$(echo "$OUTPUT" | head -c 2800)"

    if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
        PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'channel': '${SLACK_NOTIFICATION_CHANNEL}', 'text': sys.argv[1]}))" "$SUMMARY")
        curl -s -X POST "https://slack.com/api/chat.postMessage" \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            > /dev/null 2>&1 || echo "[WARN] Slack delivery failed" >> "$LOG_FILE"
    fi
fi

# Prune old logs (keep last 30 days)
find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true

exit 0
