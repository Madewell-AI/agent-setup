# Skills System

## Overview

Skills are markdown instruction files that give your agent domain-specific capabilities. When you invoke a skill (e.g., `/tasks`), the agent reads the skill file and follows its instructions.

## Creating a Skill

### For Claude Code

Skills live in `~/.claude/skills/` with this structure:

```
~/.claude/skills/
└── my-skill/
    └── SKILL.md
```

Skill file format:
```markdown
---
name: my-skill
description: Brief description of when to use this skill
argument-hint: "[optional usage hint]"
allowed-tools: Bash(curl *), Bash(ls *), Read, Write
---

# My Skill

## What This Does
Explain the skill's purpose.

## Instructions
Step-by-step instructions for the agent.

## API Reference (if applicable)
Document any APIs, commands, or tools the skill uses.
```

Register the skill in your `~/CLAUDE.md`:
```markdown
## Skills
- `/my-skill` — description of what it does
```

### For Codex CLI

Skills live in `~/.agent/skills/` as markdown files:

```
~/.agent/skills/
└── my-skill.md
```

Reference them in `~/AGENTS.md`:
```markdown
## Skills
When the user requests [skill domain], read `~/.agent/skills/my-skill.md` first.
```

Since Codex doesn't have a native skill/slash-command system, skills are invoked by the agent reading the file when it recognizes a relevant request (guided by the AGENTS.md instruction).

## Example Skills

### Task Management
```markdown
---
name: tasks
description: Create, update, and manage tasks
---

# Task Management

## API
- List tasks: GET https://api.example.com/tasks
- Create task: POST https://api.example.com/tasks
- Update task: PUT https://api.example.com/tasks/{id}

## Authentication
Use the API key from ~/.agent/.env (TASK_API_KEY).

## Instructions
- When creating a task, always include a title and due date
- When listing tasks, show them grouped by status
```

### Email Triage
```markdown
---
name: email
description: Read, triage, and respond to emails
---

# Email Skill

## Instructions
1. Fetch unread emails
2. Categorize: urgent, needs-response, informational, spam
3. For urgent: summarize and flag immediately
4. For needs-response: draft a reply for approval
5. For informational: add to daily summary
6. NEVER send an email without explicit approval
```

## Best Practices

- Keep skills focused — one domain per skill
- Include API docs inline so the agent doesn't need to look them up
- Specify safety rules (e.g., "never send without approval")
- Use `allowed-tools` to restrict what the skill can do (Claude Code only)
- Test skills manually before relying on them in production
