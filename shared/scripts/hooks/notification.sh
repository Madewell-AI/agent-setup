#!/usr/bin/env bash
# Notification Hook — Send alerts to Slack when the agent needs attention
# Claude Code only (Codex CLI doesn't have a Notification hook)

set -euo pipefail

AGENT_DIR="${HOME}/.agent"

# Skip notifications from background workers — they already handle their own
# notification channels. Detect by checking if parent process is a headless
# agent session (spawned via spawn-worker.sh or webhook listener).
PARENT_CMD=$(ps -o args= -p $PPID 2>/dev/null || true)
if echo "$PARENT_CMD" | grep -q -- '-p'; then
    exit 0
fi

# Load env for Slack credentials
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

# Read notification from stdin (Claude Code passes JSON)
INPUT=$(cat)
REASON=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason','needs_attention'))" 2>/dev/null || echo "needs_attention")
MESSAGE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null || echo "")

# Map reason codes to human-readable text
case "$REASON" in
    "idle")
        TEXT="Agent is waiting for your input."
        ;;
    "permission")
        TEXT="Agent needs permission to proceed. Check your session."
        ;;
    "error")
        TEXT="Agent hit an error and needs your attention."
        ;;
    *)
        TEXT="Agent needs your attention ($REASON)."
        ;;
esac

if [ -n "$MESSAGE" ]; then
    TEXT="$TEXT\n>$MESSAGE"
fi

# Send to Slack
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
    curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"channel\": \"${SLACK_NOTIFICATION_CHANNEL}\", \"text\": \"${TEXT}\"}" \
        > /dev/null 2>&1 || true
fi

exit 0
