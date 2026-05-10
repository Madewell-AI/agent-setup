#!/usr/bin/env bash
# Disk warning — runs disk-status.sh and posts to Slack ONLY if free space is low.
# Designed for daily cron use: silent on healthy days, alerts when free < threshold.
#
# Usage: disk-warn.sh [threshold_gb]
#   threshold_gb  — alert when free space drops below this (default: 20)
#
# Requires:
#   SLACK_BOT_TOKEN — set in your bot's .env or export before running
#   SLACK_ALERT_CHANNEL — the channel ID to post warnings to

set -uo pipefail

THRESHOLD_GB="${1:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS=$("$SCRIPT_DIR/disk-status.sh" "$THRESHOLD_GB")

if ! grep -q '^WARNING' <<<"$STATUS"; then
  exit 0
fi

# Load token from env or bot .env file
if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
  SLACK_BOT_TOKEN=$(grep -E '^SLACK_BOT_TOKEN=' "$HOME/maia-slack/.env" 2>/dev/null | cut -d= -f2-)
fi

if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
  echo "[disk-warn] no SLACK_BOT_TOKEN, cannot deliver" >&2
  exit 1
fi

CHANNEL="${SLACK_ALERT_CHANNEL:-}"
if [[ -z "$CHANNEL" ]]; then
  echo "[disk-warn] no SLACK_ALERT_CHANNEL set, cannot deliver" >&2
  exit 1
fi

TEXT=":warning: *Disk space alert*

\`\`\`
${STATUS}
\`\`\`"

PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'channel': sys.argv[1], 'text': sys.argv[2]}))" "$CHANNEL" "$TEXT")

curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null
