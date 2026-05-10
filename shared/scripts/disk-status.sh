#!/usr/bin/env bash
# Disk status — prints concise disk report.
# Exits 0 always; emits "WARNING" line when free space < threshold (default 20G).

THRESHOLD_GB="${1:-20}"
THRESHOLD_KB=$(( THRESHOLD_GB * 1024 * 1024 ))

read -r _ size_kb used_kb avail_kb pct mount < <(df -k / | awk 'NR==2')

size_gb=$(( size_kb / 1024 / 1024 ))
used_gb=$(( used_kb / 1024 / 1024 ))
avail_gb=$(( avail_kb / 1024 / 1024 ))

echo "Disk: ${used_gb}G used / ${avail_gb}G free / ${size_gb}G total (${pct})"
echo
echo "Top consumers in $HOME:"
du -h -d 1 "$HOME" 2>/dev/null | sort -hr | head -8 | sed 's/^/  /'

if (( avail_kb < THRESHOLD_KB )); then
  echo
  echo "WARNING: free space (${avail_gb}G) is below ${THRESHOLD_GB}G threshold."
  echo "Recommended: run ~/.maia/scripts/disk-cleanup.sh, then review the largest dirs above."
fi
