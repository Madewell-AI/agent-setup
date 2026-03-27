#!/usr/bin/env python3
"""
Feedback detector: analyzes user messages for correction patterns.
When a correction is detected, appends it to a feedback queue file
that the agent reads on next session start to decide what to persist as memories.

Designed to run fast (<100ms) on every UserPromptSubmit.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

HOME = Path.home()
FEEDBACK_QUEUE = HOME / ".agent" / "feedback-queue.jsonl"

# Correction signal patterns — phrases that indicate the user is correcting the agent
CORRECTION_PATTERNS = [
    # Direct corrections
    r"\bno[,.]?\s+(don'?t|not|never|stop|wrong|that'?s not)\b",
    r"\bthat'?s (wrong|incorrect|not right|not what)\b",
    r"\bdon'?t (do that|use|add|include|put|make|create)\b",
    r"\bstop (doing|adding|using|putting|making)\b",
    r"\bnever (do|use|add|include|put|make)\b",
    r"\bwrong\b.*\binstead\b",
    r"\bnot that\b",
    r"\bi (said|meant|asked for|wanted)\b",
    # Redirections
    r"\binstead[,.]?\s+(do|use|try|go|make)\b",
    r"\bactually[,.]?\s+(do|use|it'?s|I|we|the)\b",
    r"\blets? not\b",
    r"\bno[,.]?\s+use\b",
    r"\buse .+ instead\b",
    # Preferences
    r"\balways (use|do|make|put|add|include)\b",
    r"\bnever (use|do|make|put|add|include)\b",
    r"\bi prefer\b",
    r"\bfrom now on\b",
    r"\bin the future\b",
    r"\bremember (to|that|this)\b",
    # Frustration signals
    r"\bi (already|just) (told|said|asked)\b",
    r"\blike i said\b",
    r"\bagain[,.]?\s",
]

COMPILED_PATTERNS = [re.compile(p, re.IGNORECASE) for p in CORRECTION_PATTERNS]

# Minimum message length to analyze (very short messages are usually commands)
MIN_LENGTH = 15


def detect_correction(message: str) -> dict | None:
    """Check if a message contains correction signals. Returns match info or None."""
    if len(message) < MIN_LENGTH:
        return None

    matches = []
    for i, pattern in enumerate(COMPILED_PATTERNS):
        m = pattern.search(message)
        if m:
            matches.append({
                "pattern": CORRECTION_PATTERNS[i],
                "matched": m.group(0),
            })

    if not matches:
        return None

    # Confidence: more pattern matches = higher confidence
    confidence = min(len(matches) / 2.0, 1.0)  # 2+ matches = high confidence

    return {
        "timestamp": datetime.now().isoformat(),
        "message": message[:500],  # Truncate for storage
        "match_count": len(matches),
        "confidence": round(confidence, 2),
        "signals": [m["matched"] for m in matches[:3]],
    }


def append_to_queue(entry: dict):
    """Append a detected correction to the feedback queue."""
    FEEDBACK_QUEUE.parent.mkdir(parents=True, exist_ok=True)
    with open(FEEDBACK_QUEUE, "a") as f:
        f.write(json.dumps(entry) + "\n")

    # Keep queue under 50 entries (trim oldest)
    try:
        lines = FEEDBACK_QUEUE.read_text().strip().splitlines()
        if len(lines) > 50:
            FEEDBACK_QUEUE.write_text("\n".join(lines[-50:]) + "\n")
    except OSError:
        pass


def extract_user_message(raw: str) -> str:
    """Extract the user's actual message, stripping system prompts and formatting rules."""
    # Look for a user message delimiter (used in Slack-forwarded messages)
    # Customize this marker to match your bot's format
    marker = "--- User's message ---"
    idx = raw.find(marker)
    if idx != -1:
        return raw[idx + len(marker):].strip()

    # Also try a common alternative format
    marker_alt = "--- {{USER_NAME}}'s message ---"
    idx = raw.find(marker_alt)
    if idx != -1:
        return raw[idx + len(marker_alt):].strip()

    # Strip system context blocks that start with "You are..."
    if raw.lstrip().startswith("You are"):
        parts = raw.split("---")
        if len(parts) >= 3:
            return parts[-1].strip()

    # Strip formatting rules blocks appended by cron/bot runners
    for rules_marker in ["--- Slack Formatting Rules", "--- Formatting Rules"]:
        idx = raw.find(rules_marker)
        if idx != -1:
            return raw[:idx].strip()

    return raw


def main():
    parser = argparse.ArgumentParser(description="Feedback correction detector")
    parser.add_argument("message", nargs="*", default=[])
    parser.add_argument("--user-id", default="")
    parser.add_argument("--user-name", default="")
    args = parser.parse_args()

    message = " ".join(args.message) if args.message else ""
    if not message and not sys.stdin.isatty():
        try:
            data = json.load(sys.stdin)
            message = data.get("message", data.get("prompt", data.get("content", "")))
            if isinstance(message, list):
                message = " ".join(str(m) for m in message)
        except (json.JSONDecodeError, AttributeError):
            pass

    if not message:
        return

    # Strip system prompts to only analyze the user's actual words
    message = extract_user_message(message)
    # Strip [team_user:...] marker
    message = re.sub(r"\[team_user:[^\]]+\]", "", message).strip()

    result = detect_correction(message)
    if result:
        # Tag with team member info if available
        if args.user_id:
            result["user_id"] = args.user_id
        if args.user_name:
            result["user_name"] = args.user_name
        append_to_queue(result)


if __name__ == "__main__":
    main()
