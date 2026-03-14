#!/usr/bin/env bash
# SessionStart Hook — Injects context at the beginning of each session
# Works with both Claude Code and Codex CLI

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
CONFIG="${HOME}/agent-setup/config.json"
TIMEZONE=$(cat "$CONFIG" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['timezone'])" 2>/dev/null || echo "UTC")
ASSISTANT_NAME=$(cat "$CONFIG" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['assistant']['name'])" 2>/dev/null || echo "Agent")

echo "=== ${ASSISTANT_NAME} SESSION CONTEXT ==="
echo "Today: $(TZ=$TIMEZONE date '+%Y-%m-%d (%A), %H:%M %Z')"
echo ""

# Show active workers
ACTIVE_DIR="${AGENT_DIR}/workers/active"
if [ -d "$ACTIVE_DIR" ] && [ "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]; then
    echo "Active workers:"
    for f in "$ACTIVE_DIR"/*.json; do
        desc=$(python3 -c "import json; print(json.load(open('$f'))['description'])" 2>/dev/null || echo "unknown")
        echo "  - $desc"
    done
else
    echo "Active workers: none"
fi
echo ""

# Show today's daily note if it exists
TODAY=$(TZ=$TIMEZONE date '+%Y-%m-%d')
DAILY_NOTE="${HOME}/memory/${TODAY}.md"
if [ -f "$DAILY_NOTE" ]; then
    echo "Today's note:"
    head -20 "$DAILY_NOTE"
    echo ""
fi

# Show recent memory entries
MEMORY_FILE="${HOME}/memory/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
    echo "Memory loaded: $(wc -l < "$MEMORY_FILE") lines"
fi

echo "=== END SESSION CONTEXT ==="
