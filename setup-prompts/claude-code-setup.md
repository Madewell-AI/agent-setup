# Maia Self-Setup — Claude Code

You are setting up a new AI executive assistant. Follow these steps exactly.

## Step 1: Read Configuration

Read ~/agent-setup/config.json to get the user's settings (name, timezone, assistant name, etc.).

## Step 2: Generate CLAUDE.md

Read the template at ~/agent-setup/claude-code/CLAUDE.md.template. Replace all {{VARIABLE}} placeholders with values from config.json:
- {{ASSISTANT_NAME}} → assistant.name
- {{USER_NAME}} → user.name
- {{USER_LOWERCASE}} → user.name in lowercase, spaces replaced with dashes
- {{TIMEZONE}} → user.timezone
- {{LOCATION}} → user.location
- {{USER_ROLE}} → user.role (if set, otherwise remove that line)

Write the result to ~/CLAUDE.md

## Step 3: Install Hooks

Copy ~/agent-setup/claude-code/settings.json to ~/.claude/settings.json (merge with existing if present — don't overwrite other settings).

## Step 4: Install Scripts

Copy all scripts from ~/agent-setup/shared/scripts/ to ~/.agent/scripts/
Make all .sh files executable: chmod +x ~/.agent/scripts/*.sh ~/.agent/scripts/hooks/*.sh

## Step 5: Set Up Memory

Create the Claude Code memory directory:
```
mkdir -p ~/.claude/projects/-home-$(echo $USER | tr '[:upper:]' '[:lower:]' | tr ' ' '-')/memory/
```

Read ~/agent-setup/shared/memory/MEMORY.md.template, replace variables, and write to:
~/.claude/projects/-home-$(echo $USER | tr '[:upper:]' '[:lower:]' | tr ' ' '-')/memory/MEMORY.md

## Step 6: Set Up Knowledge Graph

Copy ~/agent-setup/shared/life/README.md to ~/life/README.md (if ~/life/ doesn't already have content).
Create the directory structure:
```
mkdir -p ~/life/{projects,areas/{companies,people,operations,personal},resources,archives}
```

## Step 7: Set Up Cron System

Copy cron files:
```
mkdir -p ~/.agent/cron
cp ~/agent-setup/shared/cron/manage.sh ~/.agent/cron/
cp ~/agent-setup/shared/cron/run-job.sh ~/.agent/cron/
cp ~/agent-setup/shared/cron/jobs.example.json ~/.agent/cron/jobs.json
chmod +x ~/.agent/cron/*.sh
```

## Step 8: Set Up Heartbeat Timer

Create a systemd user timer for the heartbeat (worker monitor):

~/.config/systemd/user/agent-heartbeat.service:
```
[Unit]
Description=Agent Worker Heartbeat

[Service]
Type=oneshot
ExecStart=/home/%u/.agent/scripts/heartbeat.sh
```

~/.config/systemd/user/agent-heartbeat.timer:
```
[Unit]
Description=Agent Heartbeat Timer

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it:
```
systemctl --user daemon-reload
systemctl --user enable --now agent-heartbeat.timer
```

## Step 9: Set Up Agent .env File

Create ~/.agent/.env with placeholder values for Slack integration:
```
# Slack credentials — fill these in after setting up the Slack bot
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_NOTIFICATION_CHANNEL=your-notifications-channel-id
```

## Step 10: Install Cron Jobs

Run: `~/.agent/cron/manage.sh install`

This will create systemd timers for all jobs defined in jobs.json. The nightly memory consolidation job is enabled by default. The morning summary and weekly review are disabled — enable them when ready.

## Step 11: Verify

Run each hook script manually to verify they work:
```
echo '{"prompt": "test message"}' | bash ~/.agent/scripts/hooks/session-start.sh
echo '{"prompt": "test recall"}' | bash ~/.agent/scripts/hooks/auto-recall.sh
```

Check the heartbeat timer is active:
```
systemctl --user list-timers | grep agent-heartbeat
```

## Step 12: Report

Tell the user:
- What was set up successfully
- What needs manual configuration:
  - Slack bot setup (see ~/agent-setup/docs/slack-bot-setup.md)
  - Fill in ~/.agent/.env with Slack credentials after bot is created
  - Enable additional cron jobs as desired (manage.sh enable <id>)
  - Create custom skills at ~/.claude/skills/ for domain-specific capabilities
- The feedback detection system is active — corrections the user makes will be automatically queued and can be reviewed with: python3 ~/.agent/scripts/process-feedback.py
- Suggest they read the docs at ~/agent-setup/docs/ for detailed guides on each system
