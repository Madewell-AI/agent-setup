---
name: example-skill
description: An example skill to demonstrate the skill file format. Use as a template for creating your own skills.
argument-hint: "[topic]"
allowed-tools: Bash(echo *), Read, Write
---

# Example Skill

This is a template skill file. Copy this to create your own skills.

## When to Use
Describe when this skill should be invoked.

## Instructions

1. First, do this...
2. Then, do that...
3. Finally, report the result.

## API Reference (if applicable)

```bash
# Example API call
curl -s -X GET "https://api.example.com/endpoint" \
    -H "Authorization: Bearer $API_KEY"
```

## Rules
- Always confirm before taking external actions
- Never expose credentials in responses
