# Maia

> Build your own AI executive assistant — powered by Claude Code or Codex CLI.

Maia is an open-source framework for creating a personal AI agent that runs 24/7 on a VM (or local machine), communicates through Slack, remembers everything, and handles tasks autonomously.

## What You Get

- **Persistent Memory** — 4-layer memory system (durable facts, daily notes, knowledge graph, session notes) with automatic recall on every message
- **Self-Improving Feedback** — Automatically detects when you correct the agent and queues corrections for review, preventing the same mistakes across sessions
- **Slack Bot Interface** — Chat with your agent through Slack with full thread support, file sharing, and live status updates
- **Background Workers** — Spawn long-running tasks that report back when done
- **Scheduled Jobs** — Cron system for recurring autonomous tasks (morning summaries, inbox triage, etc.)
- **Webhook Processing** — Receive and act on external events (email, GitHub, etc.)
- **Skills System** — Modular, markdown-based skill files for domain-specific capabilities
- **Excalidraw Diagrams** — Self-hosted Excalidraw instance with 1,000+ library icons for programmatic diagram creation
- **Disk Management** — Automated disk monitoring, cleanup scripts, and low-space Slack alerts
- **Security** — Trusted channel enforcement, prompt injection defense, VM hardening
- **Dual Engine Support** — Works with both Claude Code (Anthropic) and Codex CLI (OpenAI)

## Architecture

```
Your VM / Machine
├── CLAUDE.md or AGENTS.md     ← Identity, rules, skills registry
├── .claude/ or .codex/        ← Hooks, skills, settings
├── .agent/                    ← Scripts, cron, workers
│   ├── scripts/
│   │   ├── hooks/             ← Lifecycle hooks (session start, auto-recall, etc.)
│   │   ├── auto-recall.py     ← Memory search on every message
│   │   ├── feedback-detector.py ← Correction detection + feedback queue
│   │   ├── process-feedback.py  ← Review + persist queued corrections
│   │   ├── spawn-worker.sh    ← Background task spawner
│   │   ├── heartbeat.sh       ← Worker health monitor
│   │   ├── disk-status.sh     ← Disk usage report
│   │   ├── disk-cleanup.sh    ← Safe cache/artifact cleanup
│   │   └── disk-warn.sh       ← Low-disk Slack alert (for cron)
│   ├── cron/                  ← Scheduled job system
│   │   ├── jobs.json          ← Job definitions
│   │   ├── manage.sh          ← CLI for managing jobs
│   │   └── run-job.sh         ← Job executor
│   ├── excalidraw/            ← Self-hosted Excalidraw app (optional)
│   └── workers/               ← Worker state tracking
├── memory/                    ← Daily notes (auto-generated)
├── life/                      ← Knowledge graph (PARA method)
├── sessions/                  ← Conversation session notes
└── slack-bot/                 ← Slack Socket Mode bot
    └── bot.js
```

## Quick Start

### 1. Choose Your Engine

| | Claude Code | Codex CLI |
|---|---|---|
| **Provider** | Anthropic | OpenAI |
| **Model** | Claude (Opus/Sonnet/Haiku) | GPT-4o / o3 |
| **Best for** | Complex reasoning, long autonomous workflows | Budget-friendly, good coding |
| **Cost** | ~$100-200/mo (Max plan) | ~$20-200/mo (API usage) |
| **Hook system** | Full (4 hook types) | Partial (SessionStart + AfterToolUse) |

See the [setup guide](https://agent-setup-guide.vercel.app) for detailed cost breakdowns.

### 2. Clone This Repo

```bash
git clone https://github.com/madewell-ai/agent-setup.git
cd agent-setup
```

### 3. Run Setup

The fastest way: install and authenticate your chosen engine, then paste the setup prompt into it. The agent will configure itself.

**Claude Code:**
```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Authenticate
claude auth

# Run the self-setup prompt
claude -p "$(cat setup-prompts/claude-code-setup.md)"
```

**Codex CLI:**
```bash
# Install Codex
brew install openai-codex

# Authenticate
codex auth

# Run the self-setup prompt
codex "$(cat setup-prompts/codex-setup.md)"
```

### 4. Set Up Slack Bot

Follow the [Slack Bot Setup Guide](docs/slack-bot-setup.md) to create your Slack app and connect it.

### 5. Customize

Edit `config.json` to set your:
- Assistant name
- Your name and timezone
- Slack channel mappings
- Enabled features (memory, cron, workers, webhooks)

## Documentation

- [Full Setup Guide](docs/setup.md)
- [VM Setup (Hetzner)](docs/vm-setup.md)
- [Slack Bot Setup](docs/slack-bot-setup.md)
- [Memory System](docs/memory.md)
- [Cron Jobs](docs/cron.md)
- [Workers](docs/workers.md)
- [Skills](docs/skills.md)
- [Excalidraw Diagrams](docs/excalidraw.md)
- [Security](docs/security.md)
- [Codex CLI Differences](docs/codex-differences.md)

## How It Works

1. **You message your agent in Slack** → The Slack bot receives it via Socket Mode
2. **The bot spawns a CLI session** → `claude -p` or `codex` with your message + system prompt
3. **Hooks fire** → SessionStart injects today's context; UserPromptSubmit searches memory for relevant info
4. **The agent responds** → With full tool access (file read/write, bash, web search, etc.)
5. **Thread continuity** → Each Slack thread maps to a persistent session
6. **Background work** → Long tasks spawn as workers; cron handles scheduled jobs
7. **Memory consolidation** → Nightly cron reviews the day, writes notes, updates the knowledge graph

## License

MIT — use it however you want.

## Credits

Created by Ben Valentin. Built at Madewell AI.

If you want a fully managed, hosted version or need help customizing this for your business, [get in touch](https://madewell.ai/contact).
