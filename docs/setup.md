# Full Setup Guide

## Prerequisites

- A Linux machine (VM or local) with Ubuntu 22.04+ or similar
- SSH access (for VM setups)
- A Slack workspace where you can create apps
- An Anthropic account (for Claude Code) or OpenAI account (for Codex CLI)

## Option A: VM Setup (Recommended)

A dedicated VM gives your agent 24/7 uptime, isolated from your personal machine.

### 1. Create a VM

**Hetzner Cloud (recommended for price/performance):**
- Sign up at hetzner.com/cloud
- Create a new project
- Add your SSH key under Security > SSH Keys
- Create a server:
  - Location: Choose closest to you
  - Image: Ubuntu 24.04
  - Type: CPX21 (3 vCPU, 4GB RAM, €8/mo) is sufficient to start. Upgrade to CPX31 (4 vCPU, 8GB RAM) if you run many concurrent tasks
  - SSH Key: Select your key
  - Name: Whatever you want (e.g., "agent-vm")

**Other providers:** DigitalOcean ($24/mo), Linode ($24/mo), AWS Lightsail ($20/mo) — any VPS works.

### 2. Secure the VM

SSH into your server as root and run the hardening script:

```bash
ssh root@YOUR_SERVER_IP
curl -sL https://raw.githubusercontent.com/madewell-ai/agent-setup/main/vm-setup/harden.sh | bash -s -- YOUR_USERNAME
```

This will:
- Update all packages
- Enable automatic security updates
- Harden SSH (key-only, no root login, fail2ban)
- Configure UFW firewall
- Create a non-root user
- Install essential tools

**IMPORTANT:** Test SSH access as your new user before closing the root session:
```bash
ssh YOUR_USERNAME@YOUR_SERVER_IP
```

### 3. Install the Software Stack

As your non-root user:

```bash
curl -sL https://raw.githubusercontent.com/madewell-ai/agent-setup/main/vm-setup/install-stack.sh | bash
```

This will interactively install Node.js, Python, and your chosen AI engine.

### 4. Clone and Configure

```bash
git clone https://github.com/madewell-ai/agent-setup.git ~/agent-setup
cd ~/agent-setup
cp config.json config.json.bak
```

Edit config.json with your details:
```bash
nano config.json
```

Set your name, timezone, location, and assistant name.

### 5. Run the Self-Setup Prompt

This is the magic step — your AI agent configures itself.

**Claude Code:**
```bash
claude -p "$(cat ~/agent-setup/setup-prompts/claude-code-setup.md)"
```

**Codex CLI:**
```bash
codex "$(cat ~/agent-setup/setup-prompts/codex-setup.md)"
```

The agent will read the setup instructions, install hooks, create the memory system, set up cron jobs, and report back what it did.

### 6. Set Up Slack Bot

See [Slack Bot Setup](slack-bot-setup.md) for the full walkthrough.

## Option B: Local Machine

You can run this on your own computer, but the agent won't be available 24/7 (cron jobs and workers stop when the machine sleeps).

Follow the same steps starting from Step 3, but skip the VM creation and hardening.

## Verifying Your Setup

After setup, check that everything is working:

```bash
# Test session start hook
echo '{"prompt": "test"}' | bash ~/.agent/scripts/hooks/session-start.sh

# Test auto-recall
bash ~/.agent/scripts/hooks/auto-recall.sh "test memory recall"

# Check cron jobs
~/.agent/cron/manage.sh list

# Test the Slack bot (if set up)
systemctl --user status agent-slack
```

## Adding Skills

Skills are markdown instruction files that give your agent domain-specific knowledge. See [Skills](skills.md) for how to create and register them.

## Adding Cron Jobs

Edit `~/.agent/cron/jobs.json` to add scheduled tasks. See [Cron Jobs](cron.md) for the job schema and examples.
