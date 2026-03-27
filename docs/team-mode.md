# Team Mode

Run a shared Maia instance that your entire team can interact with via Slack.

## Overview

By default, Maia runs in **personal mode** — one user, responds to every message. Team mode changes two things:

1. **Mention-only activation** — The bot only responds when @mentioned or in thread follow-ups to conversations it started. Random channel messages are ignored.
2. **User identity injection** — Every message includes who sent it (name, role, optional context). The agent adapts responses to the person it's talking to.

## Configuration

Set `"mode": "team"` in `config.json`:

```json
{
  "mode": "team",
  "assistant": {
    "name": "Maia",
    "role": "AI Team Assistant",
    "vibe": "Helpful, direct, execution-focused"
  },
  "team": {
    "org_name": "Acme Corp",
    "users": {
      "Sarah Chen": {
        "role": "Senior Engineer",
        "context": "Backend lead. Primary languages: Go, Python. Owns the auth service."
      },
      "U08ABC123": {
        "role": "Product Manager",
        "context": "Owns the mobile app roadmap. Prefers bullet-point summaries."
      }
    }
  },
  "user": {
    "name": "Admin",
    "timezone": "America/New_York"
  }
}
```

### User Roster

The `team.users` object maps user identifiers to their role and context. Keys can be:

- **Slack user ID** (e.g., `U08ABC123`) — most reliable, never changes
- **Display name** (e.g., `Sarah Chen`) — matched against Slack profile

Both `role` and `context` are optional. If omitted, the bot falls back to the user's Slack profile title. If a user isn't in the roster at all, the bot still works — it just uses their Slack profile info.

The `context` field is injected into the prompt when that user sends a message. Use it for:
- Technical expertise and primary languages
- Areas of ownership
- Communication preferences
- Any context that helps the agent give better answers

### Organization Name

Set `team.org_name` to your company/team name. This appears in the generated CLAUDE.md so the agent knows what organization it serves.

## How It Works

### Message Flow (Team Mode)

1. Someone @mentions the bot in a channel → bot responds in a thread
2. Anyone can reply in that thread → bot continues the conversation
3. Each reply includes the sender's identity and role
4. Top-level messages without @mention → ignored

### DMs

Direct messages work the same in both modes — the bot always responds to DMs regardless of mode.

### User Resolution

When a message arrives, the bot:
1. Calls Slack's `users.info` API to get the sender's real name, display name, and title
2. Checks `team.users` for a matching entry (by user ID, then by name)
3. Merges the Slack profile with any config-defined role/context
4. Injects this into the prompt: `--- Message from Sarah Chen (Senior Engineer) ---`

User info is cached in memory for the lifetime of the bot process.

## Recommended Setup

### Separate Infrastructure

For team use, we recommend a dedicated setup:

- **Dedicated VM** — separate from any personal Maia instance
- **Dedicated email** — e.g., `maia@yourcompany.com`
- **Service accounts** — use the dedicated email to create:
  - GitHub account (add as org member with appropriate permissions)
  - Vercel account or team member
  - Linear service account
  - Any other integrations

This gives you a clean audit trail (commits from "Maia", deploys from "Maia") and easy permission scoping.

### Slack App

You can either:
- Create a brand new Slack app for the team bot (recommended — clean separation)
- Reuse an existing app and just change the VM/config it points to

Follow the same [Slack Bot Setup Guide](slack-bot-setup.md) — the manifest and process are identical.

### Permissions

Think about what the team bot should and shouldn't have access to:
- Which repos can it read/write?
- Can it deploy, or only suggest changes?
- Which channels should it be in?
- Should it have access to production systems?

Configure channel-specific workdirs and system prompts in `config.json` to scope what the agent can do per channel.

## Differences from Personal Mode

| Behavior | Personal | Team |
|----------|----------|------|
| Responds to channel messages | All messages | @mentions only |
| Thread follow-ups | Always | Only if bot started the thread |
| User identity in prompt | Static (from config) | Dynamic (per-message sender) |
| DMs | Always responds | Always responds |
| CLAUDE.md "About You" section | Single user | Team/org description |
