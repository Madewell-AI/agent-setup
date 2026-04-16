#!/bin/bash
# Export an Excalidraw drawing to a high-quality PNG image.
#
# Requires a headless browser tool. This script uses the `browse` CLI
# but you can substitute Puppeteer, Playwright, or any headless Chrome wrapper.
#
# Usage: ./export.sh <drawing-id> [output-path] [port]
# Example: ./export.sh my-diagram /tmp/my-diagram.png 3200

set -e

DRAWING_ID="${1:?Usage: export.sh <drawing-id> [output-path] [port]}"
OUTPUT="${2:-/tmp/draw-${DRAWING_ID}.png}"
PORT="${3:-3200}"

# Point BROWSE to your headless browser CLI (browse, puppeteer, playwright, etc.)
BROWSE="${BROWSE_CLI:-browse}"

$BROWSE viewport 1920x1080 2>/dev/null

$BROWSE goto "http://localhost:${PORT}/d/${DRAWING_ID}?export=true" 2>/dev/null

for i in $(seq 1 20); do
    READY=$($BROWSE js "document.body.getAttribute('data-export-ready')" 2>/dev/null || echo "")
    if [[ "$READY" == *"true"* ]]; then
        break
    fi
    sleep 0.3
done

sleep 0.5

$BROWSE js "
  document.querySelectorAll('.layer-ui__wrapper > *, .App-toolbar, .App-toolbar-container, .App-menu, .App-menu_top, [class*=footer], [class*=Footer], .help-icon, .zoom-actions, .undo-redo-buttons, .HintViewer, [class*=sidebar], [class*=Sidebar], [class*=top-right]').forEach(el => el.style.display = 'none');
  document.querySelector('.excalidraw')?.style.setProperty('background', '#ffffff');
  'done'
" 2>/dev/null

sleep 0.3

$BROWSE screenshot "$OUTPUT" 2>/dev/null

echo "$OUTPUT"
