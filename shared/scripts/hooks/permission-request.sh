#!/usr/bin/env bash
# PermissionRequest hook — auto-allow .claude/ directory operations
# Workaround: --dangerously-skip-permissions still blocks .claude/ writes
# See: https://github.com/anthropics/claude-code/issues/37939

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# Extract file path from tool input (different tools use different field names)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Auto-approve any file operation targeting .claude/ directories
if [[ "$FILE_PATH" =~ /\.claude/ ]]; then
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: {
                behavior: "allow"
            }
        }
    }'
    exit 0
fi

# Default: no opinion — let normal flow continue
exit 0
