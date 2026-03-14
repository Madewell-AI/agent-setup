# Maia — VM Setup Guide (Hetzner Cloud)

## Why a VM?

A dedicated VM gives your agent:
- **24/7 uptime** — Cron jobs, workers, and the Slack bot run even when your laptop is closed
- **Isolation** — The agent's environment is separate from your personal machine
- **Consistency** — No conflicts with your local dev tools or OS updates
- **Cost efficiency** — A Hetzner CPX21 costs €8/mo (~$9) for plenty of horsepower

## Recommended Specs

| Tier | Hetzner Type | vCPU | RAM | Disk | Cost | Use Case |
|------|-------------|------|-----|------|------|----------|
| Starter | CPX21 | 3 | 4 GB | 80 GB | €8/mo | Personal assistant, light usage |
| Standard | CPX31 | 4 | 8 GB | 160 GB | €15/mo | Heavy usage, multiple concurrent tasks |
| Power | CPX41 | 8 | 16 GB | 240 GB | €28/mo | Multiple agents, heavy cron, many workers |

**Recommended:** Start with CPX21. Upgrade later if needed — Hetzner makes this easy.

## Step-by-Step Setup

### 1. Create Hetzner Account
- Go to [hetzner.com/cloud](https://www.hetzner.com/cloud/)
- Create an account and add a payment method

### 2. Add SSH Key
- In the Hetzner console, go to **Security** > **SSH Keys**
- Add your public SSH key
- If you don't have one: `ssh-keygen -t ed25519 -C "your-email@example.com"`
- Copy it: `cat ~/.ssh/id_ed25519.pub`

### 3. Create Server
- Click **Add Server**
- **Location:** Choose the closest to you (lower latency for Slack responses)
- **Image:** Ubuntu 24.04
- **Type:** CPX21 (Shared vCPU, AMD)
- **Networking:** Public IPv4 + IPv6
- **SSH Key:** Select your key
- **Cloud Config:** Leave empty
- **Name:** e.g., "my-agent"
- Click **Create & Buy Now**

### 4. Initial Access
```bash
ssh root@YOUR_SERVER_IP
```

### 5. Run Hardening Script
```bash
# Download and run the hardening script
# Replace 'myuser' with your desired username
curl -sL https://raw.githubusercontent.com/madewell-ai/agent-setup/main/vm-setup/harden.sh -o harden.sh
chmod +x harden.sh
./harden.sh myuser
```

### 6. Test Non-Root Access
In a NEW terminal (keep root session open):
```bash
ssh myuser@YOUR_SERVER_IP
```

If this works, you can close the root session. If not, troubleshoot before proceeding.

### 7. Install Software Stack
As your non-root user:
```bash
curl -sL https://raw.githubusercontent.com/madewell-ai/agent-setup/main/vm-setup/install-stack.sh -o install-stack.sh
chmod +x install-stack.sh
./install-stack.sh
```

Follow the interactive prompts to install Node.js, Python, and your chosen AI engine.

### 8. Authenticate Your Engine
```bash
# For Claude Code:
claude auth
# Follow the browser-based auth flow

# For Codex CLI:
codex auth
# Enter your API key
```

### 9. Clone and Configure
```bash
git clone https://github.com/madewell-ai/agent-setup.git ~/agent-setup
cd ~/agent-setup
nano config.json  # Edit with your details
```

### 10. Run Self-Setup
```bash
# Claude Code:
claude -p "$(cat ~/agent-setup/setup-prompts/claude-code-setup.md)"

# Codex CLI:
codex "$(cat ~/agent-setup/setup-prompts/codex-setup.md)"
```

### 11. Set Up Slack Bot
Follow [Slack Bot Setup](slack-bot-setup.md).

## Optional: Cloudflare Tunnel

If you want webhook processing (receiving events from external services):

```bash
# Install cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Login to Cloudflare
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create my-agent-tunnel

# Configure routing (edit config)
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml <<EOF
tunnel: YOUR_TUNNEL_ID
credentials-file: /home/myuser/.cloudflared/YOUR_TUNNEL_ID.json
ingress:
  - hostname: agent-webhooks.yourdomain.com
    service: http://localhost:3456
  - service: http_status:404
EOF

# Add DNS record
cloudflared tunnel route dns my-agent-tunnel agent-webhooks.yourdomain.com

# Run as a service
cloudflared service install
systemctl --user enable --now cloudflared
```

## Maintenance

### Backups
Hetzner offers snapshots — take one after initial setup:
- Hetzner Console > Your Server > Snapshots > Create Snapshot
- Cost: €0.01/GB/month

### Monitoring
- Check disk usage: `df -h`
- Check memory: `free -h`
- Check agent services: `systemctl --user list-units --type=service`

### Updating the Framework
```bash
cd ~/agent-setup
git pull origin main
```

Then re-run the setup prompt to apply any changes.

---

*Created by Ben Valentin. Built at Madewell AI.*
