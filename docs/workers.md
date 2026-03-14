# Maia — Background Workers

## Overview

Workers are headless AI agent sessions that run in the background for long-running tasks. Useful for research, code generation, builds, or anything that would block a conversation.

## Spawning a Worker

```bash
~/.agent/scripts/spawn-worker.sh "description" "detailed prompt" [workdir]
```

Example:
```bash
~/.agent/scripts/spawn-worker.sh \
    "Research competitor pricing" \
    "Research the top 5 competitors in our space and compile their pricing tiers into a summary document at ~/research/competitor-pricing.md" \
    ~/
```

## Worker Lifecycle

1. **Spawn** — Creates a detached process with metadata in `~/.agent/workers/active/`
2. **Running** — Worker writes `[STATUS: ...]` markers to its log as it progresses
3. **Complete** — Worker writes `[DONE: summary]` when finished
4. **Monitor** — Heartbeat script (every 15 min) detects completed workers and notifies you

## Checking Workers

```bash
# List active workers
ls ~/.agent/workers/active/

# View a worker's log
cat ~/.agent/workers/logs/WORKER-ID.log

# Check the latest status
grep '\[STATUS:' ~/.agent/workers/logs/WORKER-ID.log | tail -1
```

## Worker Protocol

Workers are instructed to write these markers to stdout:
- `[STATUS: brief description]` — Progress updates (write these periodically)
- `[DONE: brief summary]` — Task complete
- `[FAILED: reason]` — Task failed

The heartbeat script watches for these markers and sends Slack notifications.

## Heartbeat

The heartbeat runs every 15 minutes via systemd timer:
- Checks if each active worker's process is still running
- Reads status markers from logs
- Moves finished workers to `~/.agent/workers/completed/`
- Sends Slack notifications for completions and failures
- Prunes old logs (30+ days)

## Tips

- Keep worker descriptions short — they show up in Slack notifications
- Workers inherit the full tool set of the AI engine (file access, bash, web, etc.)
- Workers run with `--dangerously-skip-permissions` (Claude) or `--approval-mode full-auto` (Codex) for unattended operation
- Very long tasks (>30 min) should write periodic `[STATUS:]` markers so you know they're progressing

---

*Created by Ben Valentin. Built at Madewell AI.*
