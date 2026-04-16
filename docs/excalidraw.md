# Maia — Excalidraw Integration

Self-hosted Excalidraw instance that lets your agent create, edit, and export professional diagrams programmatically.

## What You Get

- **Full Excalidraw editor** — accessible via browser at your chosen domain/port
- **File-based storage** — drawings saved as `.excalidraw` JSON files, no database needed
- **Library system** — pre-loaded icon packs (AWS, GCP, Azure, Kubernetes, IT logos, etc.)
- **Compose CLI** — Python script to programmatically build diagrams from library items
- **REST API** — create, read, update drawings and search libraries
- **Export mode** — render drawings to PNG via headless browser
- **Auto-save** — 2-second debounce saves as you edit in the browser

## Setup

### 1. Copy the app

```bash
cp -r agent-setup/shared/excalidraw ~/draw
cd ~/draw
```

### 2. Install dependencies

```bash
npm install
```

### 3. Add library packs (optional but recommended)

Download `.excalidrawlib` files from [Excalidraw Libraries](https://libraries.excalidraw.com/) or other sources and place them in `~/draw/libraries/`.

Then build the search index:

```bash
python3 build-index.py
```

This creates `libraries/item-index.json` which powers the search API and compose script.

### 4. Build and start

```bash
npm run build
npm run start -- -p 3200
```

### 5. Set up as a service (recommended)

For 24/7 operation, install the systemd user service:

```bash
cp draw.service ~/.config/systemd/user/draw.service
# Edit the service file to adjust paths if needed
systemctl --user daemon-reload
systemctl --user enable --now draw.service
```

### 6. Expose publicly (optional)

Use a Cloudflare tunnel, nginx reverse proxy, or similar to expose port 3200 at your chosen domain (e.g., `draw.yourdomain.com`).

Example with Cloudflare tunnel:
```bash
cloudflared tunnel route dns <tunnel-name> draw.yourdomain.com
```

### 7. Register the skill

Add to your `~/CLAUDE.md`:
```markdown
## Skills
- `/draw` — Create and manage Excalidraw diagrams
```

Copy the skill file:
```bash
cp agent-setup/claude-code/skills/excalidraw/SKILL.md ~/.claude/skills/draw/SKILL.md
```

Update the paths in the skill file to match your setup.

## Adding Library Packs

Excalidraw has a community library ecosystem. To add new icon packs:

1. Download `.excalidrawlib` files from:
   - [Excalidraw Libraries](https://libraries.excalidraw.com/)
   - GitHub repos with Excalidraw library files
   - Export from the Excalidraw web app

2. Place them in `~/draw/libraries/`

3. Rebuild the index:
   ```bash
   cd ~/draw && python3 build-index.py
   ```

Popular library packs for technical diagrams:
- AWS Architecture Icons
- GCP Icons
- Azure Icons
- Kubernetes
- Software Architecture
- IT Logos (Docker, React, Kafka, etc.)
- BPMN (Business Process)
- UX Wireframes
- Mobile UI Components

## How the Agent Uses It

Once set up, your agent can:

1. **Search for icons**: `python3 compose.py search "lambda"`
2. **Compose diagrams**: Use compose.py to position library items, add arrows and labels
3. **Create via API**: POST combined elements to create a drawing
4. **Share links**: Give you the URL to view/edit in browser
5. **Export PNGs**: Render to image for sharing in Slack, docs, etc.

The agent builds diagrams entirely through the CLI and API — no browser interaction needed.

## File Structure

```
~/draw/
├── src/app/                  # Next.js app source
│   ├── page.tsx              # Home page (drawing index)
│   ├── d/[id]/page.tsx       # Drawing editor page
│   └── api/                  # REST API routes
│       ├── drawings/         # CRUD for drawings
│       └── library/          # Search and retrieve library items
├── drawings/                 # Saved drawings (.excalidraw files)
├── libraries/                # Icon packs (.excalidrawlib files)
│   └── item-index.json       # Search index (built by build-index.py)
├── compose.py                # CLI for composing diagrams from library items
├── build-index.py            # Builds the library search index
├── export.sh                 # Export drawings to PNG
└── draw.service              # Systemd service file
```

---

*Created by Ben Valentin. Built at Madewell AI.*
