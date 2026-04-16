---
name: draw
description: Create, manage, and export Excalidraw diagrams. Use when asked to create architecture diagrams, flowcharts, wireframes, or any visual diagram.
argument-hint: "[drawing name or action]"
allowed-tools: Bash(python3 *), Bash(curl *), Bash(cd *), Read, Write
---

# Draw — Excalidraw Diagrams

Create and manage Excalidraw drawings via your self-hosted Excalidraw app.

## Architecture

- App: Next.js at `~/draw/`, port 3200
- Drawings stored: `~/draw/drawings/{id}.excalidraw`
- Libraries: `~/draw/libraries/` (icon packs as `.excalidrawlib` files)
- Compose script: `~/draw/compose.py`
- Service: `draw.service` (systemd user)

## PRIORITY: Use Library Items

Always prefer library items over raw shapes when an appropriate icon/component exists. Library items have professional icons, logos, and pre-styled components.

### Search for items
```bash
cd ~/draw && python3 compose.py search "docker"
```

### Get item elements positioned at (x, y)
```bash
cd ~/draw && python3 compose.py "it-logos/Docker" --x 100 --y 200 --size 80
```
Returns JSON array of elements ready to merge into a drawing.

### List all libraries
```bash
cd ~/draw && python3 compose.py list
```

## Workflow for Creating Diagrams

1. Search: `python3 compose.py search "query"`
2. Get elements: `python3 compose.py "lib/ItemName" --x X --y Y --size S`
3. Merge into drawing elements array
4. Add labels/arrows/connectors between library items
5. POST the combined drawing to the API

### Example: Architecture Diagram

```bash
cd ~/draw

LAMBDA=$(python3 compose.py "aws-serverless/Lambda" --x 100 --y 100 --size 50)
DYNAMO=$(python3 compose.py "aws-serverless/DynamoDB" --x 400 --y 100 --size 50)

python3 -c "
import json
elements = []
elements.extend(json.loads('$LAMBDA'))
elements.extend(json.loads('$DYNAMO'))
print(json.dumps({'id':'my-arch','name':'Architecture','elements':elements}))
" | curl -s -X POST http://localhost:3200/api/drawings \
  -H 'Content-Type: application/json' -d @-
```

## API

### Create a drawing
```bash
curl -s -X POST http://localhost:3200/api/drawings \
  -H "Content-Type: application/json" \
  -d '{"id":"my-drawing","name":"My Drawing","elements":[...]}'
```

### Get/Update a drawing
```bash
curl -s http://localhost:3200/api/drawings/{id}
curl -s -X PUT http://localhost:3200/api/drawings/{id} \
  -H "Content-Type: application/json" -d '{...}'
```

### Search library items
```bash
curl -s "http://localhost:3200/api/library/search?q=docker"
```

### Get library item elements
```bash
curl -s "http://localhost:3200/api/library/items?key=aws-serverless/Lambda"
```

## Raw Element Creation

When no library item exists, create elements directly.

### Element Types
- `rectangle` — Boxes, cards, containers
- `ellipse` — Circles, ovals
- `diamond` — Decision points
- `arrow` — Connections
- `line` — Dividers
- `text` — Labels

### Required Properties
```json
{
  "type": "rectangle", "id": "unique-id",
  "x": 100, "y": 100, "width": 200, "height": 100,
  "angle": 0, "version": 1, "versionNonce": 1,
  "isDeleted": false, "groupIds": [], "opacity": 100, "seed": 12345
}
```

### Styling
```json
{
  "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
  "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
  "roughness": 0, "roundness": { "type": 3 }
}
```

### Color Palette
- Blue: `stroke: "#1971c2"`, `fill: "#a5d8ff"` — systems, info
- Green: `stroke: "#2f9e44"`, `fill: "#b2f2bb"` — success, data
- Yellow: `stroke: "#f08c00"`, `fill: "#ffec99"` — decisions, warnings
- Red: `stroke: "#e03131"`, `fill: "#ffc9c9"` — errors, critical
- Purple: `stroke: "#7048e8"`, `fill: "#d0bfff"` — AI, agents
- Gray: `stroke: "#495057"`, `fill: "#dee2e6"` — secondary
- Teal: `stroke: "#0c8599"`, `fill: "#99e9f2"` — data flow

### Text
fontSize guide — Title `28`, Header `20`, Label `16`, Caption `14`. fontFamily: `2` (Helvetica) default.

### Arrows
`points` relative to (x,y). `endArrowhead`: `"arrow"`, `"triangle"`, `"bar"`, `"circle"`, or `null`.

## Icon Card Pattern

Place library icons inside cards for clean, consistent layouts:

1. Rounded rectangle card (light fill, subtle border)
2. Library icon centered inside the card (use --size ~45-55)
3. Label text centered below the icon, inside the card

Standard card: `120w x 100h`, icon at `--size 50` centered, label 14px below.

## Layout Rules
- 100px between major sections, 50px between related items, 20px minor gaps
- Align to 20px grid
- Left-to-right or top-to-bottom flow
- `roughness: 0` and `fontFamily: 2` for professional output

## Exporting to PNG

```bash
~/draw/export.sh <drawing-id> [output-path]
```

## Complete Workflow
1. Search libraries for relevant icons/components
2. Use compose.py to get positioned elements
3. Wrap each icon in a card (rounded rect + label)
4. Add arrows and connectors between cards
5. POST to API
6. Export PNG: `~/draw/export.sh {id} /tmp/{id}.png`
7. View at: `http://localhost:3200/d/{id}`
