#!/usr/bin/env bash
# Heartbeat — Monitor background workers, detect completions, send notifications
# Run via systemd timer every 15 minutes

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
ACTIVE_DIR="${AGENT_DIR}/workers/active"
COMPLETED_DIR="${AGENT_DIR}/workers/completed"

mkdir -p "$ACTIVE_DIR" "$COMPLETED_DIR"

# Load Slack credentials from agent .env
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

notify() {
    local message="$1"

    if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
        local payload
        payload=$(python3 -c "import json,sys; print(json.dumps({'channel': '${SLACK_NOTIFICATION_CHANNEL}', 'text': sys.argv[1]}))" "$message")
        curl -s -X POST "https://slack.com/api/chat.postMessage" \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            > /dev/null 2>&1 || true
    elif [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$(echo "$message" | sed 's/"/\\"/g')\"}" \
            > /dev/null 2>&1 || true
    fi
}

# Exit early if no active workers
shopt -s nullglob
ACTIVE_FILES=("$ACTIVE_DIR"/*.json)
[[ ${#ACTIVE_FILES[@]} -eq 0 ]] && exit 0

RUNNING=0

for worker_file in "${ACTIVE_FILES[@]}"; do
    [[ -f "$worker_file" ]] || continue

    ID=$(python3 -c "import json; print(json.load(open('$worker_file'))['id'])")
    PID=$(python3 -c "import json; print(json.load(open('$worker_file'))['pid'])")
    DESC=$(python3 -c "import json; print(json.load(open('$worker_file'))['description'])")
    LOG_FILE=$(python3 -c "import json; print(json.load(open('$worker_file')).get('log_file', ''))")

    # Check if process is still running
    if [ "$PID" != "null" ] && [ "$PID" != "None" ] && kill -0 "$PID" 2>/dev/null; then
        # Still running — update metadata with latest status
        RUNNING=$((RUNNING + 1))
        LAST_STATUS="running..."
        if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
            LAST_STATUS=$(grep "\[STATUS:" "$LOG_FILE" 2>/dev/null | tail -1 || echo "running...")
        fi
        python3 - <<PYEOF
import json
with open('$worker_file') as f: d = json.load(f)
d['last_status'] = """$LAST_STATUS"""
d['last_update'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$worker_file', 'w') as f: json.dump(d, f, indent=2)
PYEOF
    else
        # Process has ended — analyze results
        LOG_TAIL=""
        DONE_LINE=""
        FAILED_LINE=""
        if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
            LOG_TAIL=$(tail -20 "$LOG_FILE" | head -c 1500)
            DONE_LINE=$(grep "\[DONE:" "$LOG_FILE" 2>/dev/null | tail -1 || true)
            FAILED_LINE=$(grep "\[FAILED:" "$LOG_FILE" 2>/dev/null | tail -1 || true)
        fi

        FINAL_STATUS="completed"
        [[ -n "$FAILED_LINE" ]] && FINAL_STATUS="failed"

        # Move to completed
        python3 - <<PYEOF
import json, os
with open('$worker_file') as f: d = json.load(f)
d['status'] = '$FINAL_STATUS'
d['finished_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$COMPLETED_DIR/$ID.json', 'w') as f: json.dump(d, f, indent=2)
os.remove('$worker_file')
PYEOF

        if [[ "$FINAL_STATUS" == "completed" ]]; then
            # Skip notification for routine workers that post their own results.
            # Add patterns here for workers that should complete silently.
            SKIP_NOTIFY=false
            case "$DESC" in
                # Example: skip notification for recurring triage workers
                # my-triage-*) SKIP_NOTIFY=true ;;
                *) ;;
            esac

            if [ "$SKIP_NOTIFY" = "false" ]; then
                RESULT="${DONE_LINE:-}"
                [[ -z "$RESULT" ]] && RESULT=$(echo "$LOG_TAIL" | tail -5)
                notify "[Worker done] $DESC

$RESULT"
            fi
        else
            RESULT="${FAILED_LINE:-}"
            [[ -z "$RESULT" ]] && RESULT=$(echo "$LOG_TAIL" | tail -5)
            notify "[Worker failed] $DESC

$RESULT"
        fi
    fi
done

# Report summary of running workers
if [[ $RUNNING -gt 0 ]]; then
    SUMMARY="[Heartbeat] $RUNNING active worker(s):"
    for worker_file in "$ACTIVE_DIR"/*.json; do
        [[ -f "$worker_file" ]] || continue
        D=$(python3 -c "import json; print(json.load(open('$worker_file'))['description'])")
        S=$(python3 -c "import json; d=json.load(open('$worker_file')); print(d.get('last_status', 'running...'))")
        SUMMARY="$SUMMARY
- $D: $S"
    done
    notify "$SUMMARY"
fi

# Prune old completed workers (30+ days)
find "$COMPLETED_DIR" -name "*.json" -mtime +30 -delete 2>/dev/null || true

exit 0
