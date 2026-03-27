#!/usr/bin/env python3
"""
Process feedback queue: reads detected corrections, outputs them for the agent
to decide which ones to persist as feedback memories.

Usage: python3 process-feedback.py [--clear]
  Default: prints queued corrections for review
  --clear: removes the queue after processing
"""

import json
import sys
from pathlib import Path

HOME = Path.home()
FEEDBACK_QUEUE = HOME / ".agent" / "feedback-queue.jsonl"


def main():
    clear = "--clear" in sys.argv

    if not FEEDBACK_QUEUE.exists() or FEEDBACK_QUEUE.stat().st_size == 0:
        print("No pending feedback in queue.")
        return

    entries = []
    for line in FEEDBACK_QUEUE.read_text().strip().splitlines():
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if not entries:
        print("No pending feedback in queue.")
        return

    print(f"=== FEEDBACK QUEUE ({len(entries)} items) ===")
    print("Review these corrections and save relevant ones as feedback memories.")
    print("")

    for i, entry in enumerate(entries, 1):
        conf = entry.get("confidence", 0)
        conf_label = "HIGH" if conf >= 0.75 else "MEDIUM" if conf >= 0.5 else "LOW"
        user = entry.get("user_name", "")
        user_label = f" [{user}]" if user else ""
        print(f"[{i}] ({conf_label} confidence){user_label} {entry.get('timestamp', '?')[:16]}")
        print(f"    Signals: {', '.join(entry.get('signals', []))}")
        print(f"    Message: {entry.get('message', '?')}")
        print("")

    print("=== END FEEDBACK QUEUE ===")
    print("")
    print("For each relevant item, save a feedback memory. Then clear the queue:")
    print("  python3 ~/.agent/scripts/process-feedback.py --clear")

    if clear:
        FEEDBACK_QUEUE.write_text("")
        print("\nQueue cleared.")


if __name__ == "__main__":
    main()
