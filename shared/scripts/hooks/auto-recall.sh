#!/usr/bin/env bash
# Auto-Recall Hook — Searches memory layers for context relevant to the current message
# For Claude Code: fires on UserPromptSubmit (every message, pre-response)
# For Codex CLI: called via AGENTS.md instruction (best-effort per message)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Claude Code passes JSON on stdin with the prompt
# Codex CLI may call this directly
if [ -t 0 ]; then
    # Called directly (Codex), use $1 as search terms
    PROMPT="${1:-}"
else
    # Called via hook (Claude Code), read JSON from stdin
    INPUT=$(cat)
    PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Claude Code hook format
    if isinstance(data, dict):
        print(data.get('prompt', data.get('message', '')))
    else:
        print(str(data))
except:
    print('')
" 2>/dev/null || echo "")
fi

if [ -z "$PROMPT" ]; then
    exit 0
fi

# Extract team user info if present (injected by bot.js in team mode)
# Format: [team_user:U08ABC123:Sarah Chen]
TEAM_USER_INFO=$(echo "$PROMPT" | python3 -c "
import sys, re
m = re.search(r'\[team_user:([^:]+):([^\]]+)\]', sys.stdin.read())
if m: print(m.group(1) + '\n' + m.group(2))
" 2>/dev/null || echo "")

USER_ID=""
USER_NAME=""
if [ -n "$TEAM_USER_INFO" ]; then
    USER_ID=$(echo "$TEAM_USER_INFO" | head -1)
    USER_NAME=$(echo "$TEAM_USER_INFO" | tail -1)
fi

# Run the Python recall script (with user context if in team mode)
RECALL_ARGS=("$PROMPT")
if [ -n "$USER_ID" ]; then
    RECALL_ARGS+=("--user-id" "$USER_ID" "--user-name" "$USER_NAME")
fi
python3 "${SCRIPT_DIR}/../auto-recall.py" "${RECALL_ARGS[@]}" 2>/dev/null || true

# Run feedback detector (async, non-blocking — writes corrections to queue file)
FEEDBACK_ARGS=("$PROMPT")
if [ -n "$USER_ID" ]; then
    FEEDBACK_ARGS+=("--user-id" "$USER_ID" "--user-name" "$USER_NAME")
fi
python3 "${SCRIPT_DIR}/../feedback-detector.py" "${FEEDBACK_ARGS[@]}" 2>/dev/null &
