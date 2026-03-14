#!/usr/bin/env bash
# PostToolUse / AfterToolUse Hook — Log tool usage for observability
# Works with both Claude Code (PostToolUse) and Codex CLI (AfterToolUse)

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
LOG_FILE="${AGENT_DIR}/logs/tool-usage.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Read tool info from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', data.get('tool', 'unknown')))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

# Append to log
echo "$(date -Iseconds) ${TOOL_NAME}" >> "$LOG_FILE"

# Keep log file manageable (last 500 lines)
if [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
    tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi
