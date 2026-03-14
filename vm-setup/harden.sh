#!/usr/bin/env bash
# VM Security Hardening Script
# Designed for Ubuntu 24.04 on Hetzner Cloud (works on other providers too)
# Run as root or with sudo

set -euo pipefail

echo "=== VM Security Hardening ==="
echo ""

# 1. System updates
echo "[1/8] Updating system packages..."
apt update && apt upgrade -y

# 2. Enable automatic security updates
echo "[2/8] Enabling unattended security upgrades..."
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# 3. Configure SSH hardening
echo "[3/8] Hardening SSH configuration..."
SSH_CONFIG="/etc/ssh/sshd_config.d/hardening.conf"
cat > "$SSH_CONFIG" <<'SSHEOF'
# Disable password authentication (key-only)
PasswordAuthentication no
ChallengeResponseAuthentication no

# Disable root login
PermitRootLogin no

# Limit authentication attempts
MaxAuthTries 3

# Disable X11 forwarding
X11Forwarding no

# Set idle timeout (5 minutes)
ClientAliveInterval 300
ClientAliveCountMax 2
SSHEOF

systemctl restart sshd
echo "  SSH hardened: key-only auth, no root login, 3 max attempts"

# 4. Install and configure fail2ban
echo "[4/8] Installing fail2ban..."
apt install -y fail2ban

cat > /etc/fail2ban/jail.local <<'F2BEOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
F2BEOF

systemctl enable --now fail2ban
echo "  fail2ban active: 3 SSH failures = 24hr ban"

# 5. Configure UFW firewall
echo "[5/8] Configuring UFW firewall..."
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
# Only allow HTTP/HTTPS if running a web server
# ufw allow 80/tcp
# ufw allow 443/tcp
ufw --force enable
echo "  UFW enabled: SSH only (add more rules as needed)"

# 6. Create non-root user (if running as root)
echo "[6/8] Checking user setup..."
TARGET_USER="${1:-agent}"
if ! id "$TARGET_USER" &>/dev/null; then
    echo "  Creating user: $TARGET_USER"
    adduser --disabled-password --gecos "" "$TARGET_USER"
    usermod -aG sudo "$TARGET_USER"

    # Copy SSH keys from root
    mkdir -p "/home/${TARGET_USER}/.ssh"
    if [ -f /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys "/home/${TARGET_USER}/.ssh/"
    fi
    chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/.ssh"
    chmod 700 "/home/${TARGET_USER}/.ssh"
    chmod 600 "/home/${TARGET_USER}/.ssh/authorized_keys" 2>/dev/null || true
    echo "  User created with SSH keys copied from root"
else
    echo "  User $TARGET_USER already exists"
fi

# 7. Enable systemd user lingering (for user-level services)
echo "[7/8] Enabling systemd user lingering..."
loginctl enable-linger "$TARGET_USER"
echo "  User services will persist after logout"

# 8. Install essential tools
echo "[8/8] Installing essential tools..."
apt install -y \
    git \
    curl \
    wget \
    jq \
    htop \
    tmux \
    trash-cli \
    build-essential

echo ""
echo "=== Hardening Complete ==="
echo ""
echo "Next steps:"
echo "  1. Log in as: ssh ${TARGET_USER}@YOUR_SERVER_IP"
echo "  2. Install Node.js: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash"
echo "  3. Install your AI engine (Claude Code or Codex CLI)"
echo "  4. Clone agent-setup and run the setup prompt"
echo ""
echo "IMPORTANT: Test SSH access as ${TARGET_USER} before closing this session!"
