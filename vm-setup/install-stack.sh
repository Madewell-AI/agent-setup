#!/usr/bin/env bash
# Install the full software stack for the AI agent
# Run as the non-root user (not root/sudo)

set -euo pipefail

echo "=== Installing Agent Software Stack ==="
echo ""

# 1. Install NVM and Node.js
echo "[1/5] Installing Node.js via NVM..."
if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
fi
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 22
nvm use 22
nvm alias default 22
echo "  Node.js $(node --version) installed"

# 2. Install Python (via Homebrew for latest version)
echo "[2/5] Installing Python..."
if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
fi
brew install python
echo "  Python $(python3 --version) installed"

# 3. Choose and install AI engine
echo "[3/5] Installing AI engine..."
echo ""
echo "Which AI engine do you want to install?"
echo "  1) Claude Code (Anthropic) — recommended for complex autonomous workflows"
echo "  2) Codex CLI (OpenAI) — more budget-friendly"
echo "  3) Both"
echo ""
read -p "Enter choice (1/2/3): " ENGINE_CHOICE

case "$ENGINE_CHOICE" in
    1)
        npm install -g @anthropic-ai/claude-code
        echo "  Claude Code installed. Run 'claude auth' to authenticate."
        ;;
    2)
        brew install openai-codex
        echo "  Codex CLI installed. Run 'codex auth' to authenticate."
        ;;
    3)
        npm install -g @anthropic-ai/claude-code
        brew install openai-codex
        echo "  Both engines installed."
        echo "  Run 'claude auth' and/or 'codex auth' to authenticate."
        ;;
    *)
        echo "Invalid choice. Install manually later."
        ;;
esac

# 4. Install Cloudflare Tunnel (optional, for webhooks)
echo ""
echo "[4/5] Cloudflare Tunnel (optional — needed for webhooks)..."
read -p "Install Cloudflare Tunnel? (y/n): " INSTALL_TUNNEL

if [ "$INSTALL_TUNNEL" = "y" ]; then
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared.deb
    rm cloudflared.deb
    echo "  cloudflared installed. Run 'cloudflared tunnel login' to authenticate."
fi

# 5. Clone and set up the agent
echo ""
echo "[5/5] Setting up agent directory structure..."
AGENT_DIR="$HOME/.agent"
mkdir -p "$AGENT_DIR"/{scripts/hooks,workers/{active,completed,logs},cron/logs,logs}
mkdir -p "$HOME"/{memory,life/{projects,areas/{companies,people,operations,personal},resources,archives},sessions}

# Create .env template
if [ ! -f "$AGENT_DIR/.env" ]; then
    cat > "$AGENT_DIR/.env" <<'ENVEOF'
# Claude Code OAuth Token — required for headless claude -p subprocess auth
# Run `claude setup-token` in a real terminal to get this token.
# Without it, cron jobs and Slack bot subprocess calls will 401.
# CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Slack Bot Credentials (for notifications)
# SLACK_BOT_TOKEN=xoxb-your-token
# SLACK_NOTIFICATION_CHANNEL=C0000000000

# Add other service credentials here
ENVEOF
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Authenticate your AI engine: claude auth  OR  codex auth"
echo "  2. Clone agent-setup: git clone https://github.com/madewell-ai/agent-setup.git ~/agent-setup"
echo "  3. Edit config.json with your details"
echo "  4. Run the setup prompt — paste it into your AI engine and let it configure itself"
echo ""
