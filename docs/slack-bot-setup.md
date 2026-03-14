# Slack Bot Setup Guide

## Overview

The Slack bot uses Socket Mode — a WebSocket connection from your VM to Slack. No public URL or port forwarding needed. Your agent listens for messages and responds using your AI engine.

## Step 1: Create a Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** > **From a manifest**
3. Select your workspace
4. Paste the contents of `~/agent-setup/shared/slack-bot/manifest.json`
5. Update the `display_name` and `name` fields to your agent's name
6. Click **Create**

## Step 2: Enable Socket Mode

1. In your app settings, go to **Socket Mode** in the left sidebar
2. Toggle **Enable Socket Mode** to ON
3. Give your token a name (e.g., "agent-socket") and click **Generate**
4. Copy the `xapp-...` token — this is your `SLACK_APP_TOKEN`

## Step 3: Get Bot Token

1. Go to **OAuth & Permissions** in the left sidebar
2. Click **Install to Workspace** and authorize
3. Copy the `xoxb-...` token — this is your `SLACK_BOT_TOKEN`

## Step 4: Configure the Bot

```bash
cd ~/agent-setup/shared/slack-bot
cp .env.example .env
nano .env
```

Add your tokens:
```
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-level-token
```

## Step 5: Install Dependencies

```bash
cd ~/agent-setup/shared/slack-bot
npm install
```

## Step 6: Test It

```bash
node bot.js
```

Go to Slack and send a DM to your bot. It should respond!

Press Ctrl+C to stop the test.

## Step 7: Run as a Service

Create a systemd user service so the bot runs 24/7:

```bash
mkdir -p ~/.config/systemd/user

# Edit the service file with your paths
cp ~/agent-setup/shared/slack-bot/agent-slack.service ~/.config/systemd/user/
nano ~/.config/systemd/user/agent-slack.service
```

Update the paths in the service file:
- Replace `YOUR_USERNAME` with your actual username
- Update the Node.js path to match your NVM install (run `which node` to find it)

Enable and start:
```bash
systemctl --user daemon-reload
systemctl --user enable --now agent-slack
```

Check status:
```bash
systemctl --user status agent-slack
```

View logs:
```bash
journalctl --user -u agent-slack -f
```

## Step 8: Configure Channels

Edit `~/agent-setup/config.json` to map Slack channels to workdirs and system prompts.

To get a channel ID: right-click the channel name in Slack > **View channel details** > scroll to the bottom.

Example config:
```json
{
  "slack": {
    "channels": {
      "general": {
        "channel_id": "C0ABC123DEF",
        "workdir": "~",
        "system_prompt": "You are my AI assistant. Handle any request."
      },
      "coding": {
        "channel_id": "C0XYZ789GHI",
        "workdir": "~/projects/my-app",
        "system_prompt": "You are my coding assistant. Focus on the my-app project."
      }
    }
  }
}
```

## Step 9: Invite the Bot

Invite your bot to the channels you configured:
```
/invite @YourAgentName
```

## Troubleshooting

**Bot doesn't respond:**
- Check logs: `journalctl --user -u agent-slack -f`
- Verify tokens in .env are correct
- Make sure Socket Mode is enabled in the Slack app settings
- Check that the bot is invited to the channel

**"Missing SLACK_BOT_TOKEN" error:**
- Make sure .env file exists in the slack-bot directory
- Check that tokens don't have extra whitespace

**Bot responds slowly:**
- This is normal for first messages in a thread (new session)
- Follow-up messages in the same thread use session resume and are faster
- Claude Code is generally faster than Codex CLI for response generation

**Bot crashes and restarts:**
- The systemd service auto-restarts after 5 seconds
- Check logs for the error: `journalctl --user -u agent-slack --since "5 minutes ago"`
