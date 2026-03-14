# Maia — Cron Jobs

## Overview

The cron system lets your agent run scheduled tasks autonomously — morning summaries, inbox triage, memory consolidation, etc. Jobs are defined in JSON and executed by systemd timers.

## Job Schema

Jobs are defined in `~/.agent/cron/jobs.json`:

```json
{
    "id": "unique-kebab-case-id",
    "name": "Human Readable Name",
    "enabled": true,
    "schedule": "0 9 * * 1-5",
    "tz": "America/New_York",
    "prompt": "What the agent should do when this job fires",
    "workdir": "~",
    "deliver": true
}
```

Fields:
- `id` — Unique identifier (used for systemd timer names)
- `name` — Display name
- `enabled` — Whether the job is active
- `schedule` — Standard 5-field cron expression (minute hour day-of-month month day-of-week)
- `tz` — Timezone for the schedule
- `prompt` — The natural language instructions for the agent
- `workdir` — Working directory for the agent session
- `deliver` — If true, post the output to the Slack notification channel

## Managing Jobs

```bash
# List all jobs
~/.agent/cron/manage.sh list

# Install/update systemd timers from jobs.json
~/.agent/cron/manage.sh install

# Enable/disable a job
~/.agent/cron/manage.sh enable morning-summary
~/.agent/cron/manage.sh disable morning-summary

# Run a job immediately
~/.agent/cron/manage.sh run morning-summary

# View job logs
~/.agent/cron/manage.sh logs morning-summary
```

## Example Jobs

### Morning Summary (weekdays at 8am)
```json
{
    "id": "morning-summary",
    "name": "Morning Summary",
    "enabled": true,
    "schedule": "0 8 * * 1-5",
    "tz": "America/New_York",
    "prompt": "Good morning! Prepare a brief summary: 1) Today's calendar. 2) Urgent emails. 3) Top 3 priorities. 4) Upcoming deadlines. Keep it concise.",
    "workdir": "~",
    "deliver": true
}
```

### Nightly Memory Consolidation (every night at 11pm)
```json
{
    "id": "nightly-memory-consolidation",
    "name": "Nightly Memory Consolidation",
    "enabled": true,
    "schedule": "0 23 * * *",
    "tz": "America/New_York",
    "prompt": "Review today's conversations. Write a daily note to ~/memory/YYYY-MM-DD.md. Update the knowledge graph in ~/life/ if needed. Archive completed sessions.",
    "workdir": "~",
    "deliver": false
}
```

### Weekly Review (Fridays at 5pm)
```json
{
    "id": "weekly-review",
    "name": "Weekly Review",
    "enabled": true,
    "schedule": "0 17 * * 5",
    "tz": "America/New_York",
    "prompt": "Weekly review: 1) What was accomplished. 2) Open loops. 3) Priorities for next week. 4) Patterns or insights.",
    "workdir": "~",
    "deliver": true
}
```

## How It Works Internally

1. `manage.sh install` converts each job in jobs.json into a systemd user timer
2. When the timer fires, it calls `run-job.sh {job-id}`
3. `run-job.sh` reads the job config and spawns a headless AI session (`claude -p` or `codex`)
4. The session output is logged to `~/.agent/cron/logs/{job-id}/`
5. If `deliver: true`, the output is posted to Slack (truncated to 3000 chars)
6. Logs are auto-pruned after 30 days

## Key Insight

Jobs are just prompts. The "code" is natural language. This means you can create incredibly sophisticated scheduled tasks without writing any code — just describe what you want the agent to do.

---

*Created by Ben Valentin. Built at Madewell AI.*
