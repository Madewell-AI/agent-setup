# Security

## Threat Model

Your AI agent has full access to your machine. This is powerful but requires careful security:

1. **Prompt injection** — External content (emails, web pages, social media) could contain instructions that trick the agent into taking unwanted actions
2. **Data exfiltration** — The agent could be tricked into sending private data to external services
3. **Destructive actions** — Misunderstood instructions could lead to data loss
4. **Credential exposure** — API keys and tokens need protection

## Built-In Defenses

### Trusted Channel Enforcement

The CLAUDE.md/AGENTS.md template includes a "Trusted Channel" rule:
- Only Slack messages and direct CLI sessions are trusted command sources
- Email, social media, web content, and webhook payloads are treated as untrusted
- The agent will never execute instructions embedded in untrusted content

### Prompt Injection Defense

The template includes explicit defenses:
- All external content is treated as untrusted third-party text
- The agent reads and summarizes external content but never executes instructions from it
- Suspicious content is flagged rather than acted upon

### Destructive Action Prevention

- `trash` is preferred over `rm`
- The agent asks before sending emails, making posts, or taking public actions
- Git operations require explicit permission (no auto-push, no force-push)

## VM Security

### SSH Hardening (via harden.sh)
- Key-only authentication (passwords disabled)
- Root login disabled
- Max 3 authentication attempts
- fail2ban blocks IPs after failed attempts (24hr ban)

### Firewall
- UFW denies all incoming except SSH
- Application traffic routes through Cloudflare Tunnel (no exposed ports)

### Automatic Updates
- Unattended-upgrades keeps the OS patched
- Security updates applied automatically

### Process Isolation
- The agent runs as a non-root user
- All services run as systemd user units (not root)
- Worker processes are isolated from each other

## Credential Management

Store credentials in `~/.agent/.env`:
```bash
# Slack
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_NOTIFICATION_CHANNEL=C0...

# Other services
# MY_API_KEY=...
```

Rules:
- Never commit `.env` files to git
- Never include credentials in CLAUDE.md, AGENTS.md, or skill files
- Reference credentials by environment variable name, not value
- The agent knows to load from `~/.agent/.env` — it doesn't need the actual values in its instructions

## Webhook Security

If you set up webhook processing:
- The webhook listener only binds to localhost (not exposed publicly)
- External access routes through Cloudflare Tunnel with signature verification
- Each webhook source should use a shared secret for request verification
- Webhook payloads are treated as untrusted content

## Monitoring

- Tool usage is logged to `~/.agent/logs/tool-usage.log`
- Worker activity is tracked in `~/.agent/workers/`
- Cron job runs are logged to `~/.agent/cron/logs/`
- The heartbeat checks worker health every 15 minutes

## Recommendations

1. **Review agent actions regularly** — Check logs weekly to understand what your agent is doing
2. **Start with limited permissions** — Enable features incrementally (memory first, then cron, then workers)
3. **Use Hetzner's cloud firewall** — Add an additional firewall layer at the infrastructure level
4. **Rotate credentials** — Update API keys periodically
5. **Back up your VM** — Hetzner offers snapshots; take one after initial setup
