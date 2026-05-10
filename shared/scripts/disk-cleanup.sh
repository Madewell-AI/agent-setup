#!/usr/bin/env bash
# Disk cleanup — safe-to-rerun maintenance.
# Removes regenerable caches, build artifacts, and trash.
# Touches nothing project-specific (no node_modules, no source, no git data).

set -uo pipefail

LOG_DIR="$HOME/.maia/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/disk-cleanup-$(date +%Y%m%d-%H%M%S).log"

before_kb=$(df -k / | awk 'NR==2{print $3}')

reclaim() {
  local target="$1"
  if [[ -e "$target" ]]; then
    local size
    size=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
    echo "  - removing $target ($size)" | tee -a "$LOG"
    rm -rf "$target" 2>/dev/null || true
  fi
}

{
  echo "=== Disk cleanup $(date) ==="
  echo "Before: $(df -h / | awk 'NR==2{print $3" used / "$4" free"}')"
  echo

  echo "[1/5] Regenerable caches"
  reclaim "$HOME/.cache/pip"
  reclaim "$HOME/.cache/puppeteer"
  reclaim "$HOME/.cache/ms-playwright"
  reclaim "$HOME/.cache/Homebrew"
  reclaim "$HOME/.cache/uv"
  reclaim "$HOME/.cache/qmd"
  reclaim "$HOME/.cache/node-gyp"
  reclaim "$HOME/.cache/whisper"

  echo
  echo "[2/5] Package manager caches"
  command -v npm  >/dev/null && npm  cache clean --force 2>/dev/null || true
  command -v pnpm >/dev/null && pnpm store prune        2>/dev/null || true
  command -v bun  >/dev/null && rm -rf "$HOME/.bun/install/cache" 2>/dev/null || true

  echo
  echo "[3/5] Trash"
  reclaim "$HOME/.trash"
  mkdir -p "$HOME/.trash"

  echo
  echo "[4/5] Stale Next.js build dirs (>30d untouched, outside node_modules)"
  while IFS= read -r -d '' next_dir; do
    reclaim "$next_dir"
  done < <(find "$HOME" -type d -name '.next' -not -path '*/node_modules/*' -mtime +30 -prune -print0 2>/dev/null)

  echo
  echo "[5/5] Old session summaries / cron logs (>60d)"
  find "$HOME/.maia/session-summaries" -type f -mtime +60 -delete 2>/dev/null || true
  find "$HOME/.maia/cron/logs"          -type f -mtime +60 -delete 2>/dev/null || true
  find "$HOME/.maia/logs"               -type f -mtime +30 -delete 2>/dev/null || true
  find "$HOME/.maia/workers/completed"  -type f -mtime +30 -delete 2>/dev/null || true

  after_kb=$(df -k / | awk 'NR==2{print $3}')
  reclaimed_mb=$(( (before_kb - after_kb) / 1024 ))
  echo
  echo "After:  $(df -h / | awk 'NR==2{print $3" used / "$4" free"}')"
  echo "Reclaimed: ${reclaimed_mb} MB"
} 2>&1 | tee -a "$LOG"
