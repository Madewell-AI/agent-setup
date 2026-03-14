#!/usr/bin/env bash
# Notification Hook — Send alerts to Slack when the agent needs attention
# Claude Code only (Codex CLI doesn't have a Notification hook)

set -euo pipefail

AGENT_DIR="${HOME}/.agent"

# Load env for Slack credentials
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

# Read notification from stdin (Claude Code passes JSON)
INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('message', data.get('notification', str(data))))
except:
    print(sys.stdin.read())
" 2>/dev/null || echo "$INPUT")

# Skip if this is a background worker (they have their own notification system)
if [ "${IS_WORKER:-}" = "true" ]; then
    exit 0
fi

# Send to Slack
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_NOTIFICATION_CHANNEL:-}" ]; then
    curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"channel\": \"${SLACK_NOTIFICATION_CHANNEL}\", \"text\": \"${MESSAGE}\"}" \
        > /dev/null 2>&1
fi
