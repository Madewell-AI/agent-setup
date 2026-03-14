# Maia — Codex CLI Differences

## Overview

Maia supports both Claude Code and Codex CLI. While the architecture is the same, there are practical differences to be aware of.

## Feature Comparison

### Instruction Files
- **Claude Code:** `CLAUDE.md` (auto-loaded from ~ and each project dir)
- **Codex CLI:** `AGENTS.md` (auto-loaded from ~/.codex/ and project dirs)
- Both support hierarchical loading (global → project → subdirectory)

### Hooks
- **Claude Code:** 4 hook types — SessionStart, UserPromptSubmit, PostToolUse, Notification
- **Codex CLI:** 2 hook types — SessionStart, AfterToolUse
- **Missing in Codex:** UserPromptSubmit (per-message, pre-response) and Notification
- **Workaround:** AGENTS.md includes an instruction to run auto-recall manually before each response

### Memory
- **Claude Code:** Manual memory via MEMORY.md (in project-specific path)
- **Codex CLI:** Built-in automatic memory system + manual MEMORY.md
- Codex's built-in memory extracts facts from conversations automatically and injects them at session start

### Session Resume
- **Claude Code:** Full session resume via `--resume SESSION_ID`
- **Codex CLI:** No session resume — context comes from AGENTS.md and built-in memory
- This means Codex threads in Slack start fresh each time (but with memory context)

### MCP Servers
- **Claude Code:** Full MCP support, configured in settings
- **Codex CLI:** MCP support (experimental), configured in `~/.codex/config.toml`

### Tool Access
- **Claude Code:** Read, Write, Edit, Bash, Grep, Glob, Agent, WebFetch, WebSearch
- **Codex CLI:** Shell execution, file read/write, web access (via tools)
- Both have full system access when running in autonomous mode

## Reliability Comparison

### Auto-Recall
- **Claude Code:** Guaranteed via UserPromptSubmit hook (fires on every message)
- **Codex CLI:** Best-effort via AGENTS.md instruction (~90% reliable)

### Session Continuity
- **Claude Code:** Excellent — threads resume with full context
- **Codex CLI:** Good — built-in memory + AGENTS.md provide context, but no thread resume

### Autonomous Execution
- **Claude Code:** `claude -p --dangerously-skip-permissions` for unattended operation
- **Codex CLI:** `codex --approval-mode full-auto` for unattended operation

## Cost Comparison

### Claude Code
- **Max Plan (Anthropic):** $100/mo for 5x usage, $200/mo for 20x usage
- **Best for:** Complex multi-step reasoning, long autonomous workflows, heavy tool use
- **Model quality:** Claude Opus/Sonnet (strongest reasoning)

### Codex CLI
- **OpenAI API:** Pay per token — costs vary based on usage
- **Typical:** $20-80/mo for moderate personal assistant use
- **Best for:** Budget-conscious users, good coding tasks
- **Model quality:** GPT-4o / o3 (strong but less nuanced for complex orchestration)

### Bottom Line
- If budget isn't a constraint → Claude Code (better reasoning, full hook system)
- If you want to minimize cost → Codex CLI (pay-per-use, built-in memory saves some overhead)
- Both are fully capable of running the Maia framework

## Migration

Moving between engines is straightforward:
1. The shared scripts, cron system, workers, and memory all work with either engine
2. Only the instruction file (CLAUDE.md ↔ AGENTS.md) and settings (hooks config) differ
3. The Slack bot auto-detects which engine is installed

---

*Created by Ben Valentin. Built at Madewell AI.*
