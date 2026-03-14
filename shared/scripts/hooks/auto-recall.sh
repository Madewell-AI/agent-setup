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

# Run the Python recall script
python3 "${SCRIPT_DIR}/../auto-recall.py" "$PROMPT"
