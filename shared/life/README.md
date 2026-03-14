# Knowledge Graph — PARA Method

This directory stores durable knowledge using the PARA method:

## Structure

```
life/
├── projects/     ← Active projects with clear goals and deadlines
│   └── example/
│       ├── summary.md    ← Narrative overview for quick orientation
│       └── items.json    ← Atomic facts with metadata
├── areas/        ← Ongoing areas of responsibility (no end date)
│   ├── companies/
│   ├── people/
│   ├── operations/
│   └── personal/
├── resources/    ← Reference material and interests
└── archives/     ← Completed projects and inactive areas
```

## File Formats

### summary.md
Narrative overview of the entity. Read this first for quick orientation.

```markdown
# Entity Name

Brief description of what this is.

## Current Status
What's happening now.

## Key Context
Important background information.
```

### items.json
Atomic facts with metadata. Used for precise recall.

```json
[
    {
        "fact": "Specific atomic fact",
        "addedAt": "2026-03-14",
        "category": "optional category"
    }
]
```

## Maintenance

The nightly cron job (`nightly-memory-consolidation`) reviews conversations, extracts durable facts, and updates the relevant entity files. You can also update manually during conversations when learning important new information.
