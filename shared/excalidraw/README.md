# Excalidraw — Self-Hosted Drawing App

A minimal, self-hosted Excalidraw instance for your AI agent to create professional diagrams programmatically.

## Features

- Full Excalidraw editor in the browser
- File-based storage (no database)
- Library system with icon packs (AWS, GCP, Azure, Kubernetes, IT logos, etc.)
- REST API for programmatic drawing creation
- Compose CLI for building diagrams from library items
- Export mode for headless PNG rendering
- Auto-save with 2-second debounce

## Quick Start

```bash
# Copy to your home directory
cp -r shared/excalidraw ~/draw
cd ~/draw

# Install dependencies
npm install

# Build and start
npm run build
npm run start -- -p 3200
```

Visit `http://localhost:3200` to see the drawing index.

## Adding Libraries

Download `.excalidrawlib` files from [libraries.excalidraw.com](https://libraries.excalidraw.com/) and place them in `libraries/`, then build the index:

```bash
python3 build-index.py
```

## Full Documentation

See [docs/excalidraw.md](../../docs/excalidraw.md) for complete setup instructions, service configuration, and agent integration.
