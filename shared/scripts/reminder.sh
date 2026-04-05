#!/usr/bin/env bash
# Reminder System — Reliable one-shot reminders delivered via Slack
#
# Usage:
#   reminder.sh add <datetime> <message> [channel]   Add a reminder (datetime: "YYYY-MM-DD HH:MM")
#   reminder.sh list                                   List all pending reminders
#   reminder.sh check                                  Fire any due reminders (called by timer)
#   reminder.sh remove <id>                            Remove a reminder by ID
#
# Setup:
#   1. Create ~/.agent/reminders.json with content: []
#   2. Set up a systemd timer to run `reminder.sh check` every 5 minutes
#   3. Set SLACK_BOT_TOKEN and SLACK_NOTIFICATION_CHANNEL in ~/.agent/.env
#
# Why not cron for one-shot reminders?
#   Systemd calendar expressions don't reliably handle arbitrary one-shot dates.
#   This script stores reminders as JSON and checks every 5 minutes — simple and reliable.

set -euo pipefail

AGENT_DIR="${HOME}/.agent"
REMINDERS_FILE="${AGENT_DIR}/reminders.json"

# Load env for Slack credentials
if [ -f "${AGENT_DIR}/.env" ]; then
    source "${AGENT_DIR}/.env"
fi

# Ensure reminders file exists
if [ ! -f "$REMINDERS_FILE" ]; then
    echo "[]" > "$REMINDERS_FILE"
fi

cmd="${1:-help}"

case "$cmd" in

  add)
    DATETIME="${2:-}"
    MESSAGE="${3:-}"
    CHANNEL="${4:-notifications}"
    if [[ -z "$DATETIME" || -z "$MESSAGE" ]]; then
      echo "Usage: reminder.sh add \"YYYY-MM-DD HH:MM\" \"Your message\" [channel]" >&2
      exit 1
    fi
    python3 - "$DATETIME" "$MESSAGE" "$CHANNEL" "$REMINDERS_FILE" <<'PYEOF'
import json, sys, uuid
from datetime import datetime

dt_str, message, channel, reminders_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M")
except ValueError:
    print(f"Error: Invalid datetime format '{dt_str}'. Use 'YYYY-MM-DD HH:MM'", file=sys.stderr)
    sys.exit(1)

reminder_id = uuid.uuid4().hex[:8]

with open(reminders_file) as f:
    reminders = json.load(f)

reminders.append({
    "id": reminder_id,
    "datetime": dt_str,
    "message": message,
    "channel": channel,
    "status": "pending",
    "created": datetime.now().strftime("%Y-%m-%d %H:%M")
})

with open(reminders_file, "w") as f:
    json.dump(reminders, f, indent=2)

print(f"Reminder {reminder_id} set for {dt_str} -> #{channel}")
print(f"  Message: {message}")
PYEOF
    ;;

  list)
    python3 - "$REMINDERS_FILE" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    reminders = json.load(f)

pending = [r for r in reminders if r["status"] == "pending"]
if not pending:
    print("No pending reminders.")
else:
    print(f"{len(pending)} pending reminder(s):\n")
    for r in sorted(pending, key=lambda x: x["datetime"]):
        print(f"  [{r['id']}] {r['datetime']} -> #{r['channel']}")
        print(f"    {r['message']}")
        print()
PYEOF
    ;;

  check)
    # Called by systemd timer every 5 minutes — fires any due reminders
    python3 - "$REMINDERS_FILE" <<'PYEOF'
import json, subprocess, sys, os
from datetime import datetime

reminders_file = sys.argv[1]
slack_token = os.environ.get("SLACK_BOT_TOKEN", "")
notification_channel = os.environ.get("SLACK_NOTIFICATION_CHANNEL", "")

# Channel name → ID mapping. Customize this for your workspace.
# You can also use env vars: SLACK_CHANNEL_<NAME>=<ID>
channel_map = {}

def resolve_channel(name):
    """Resolve a channel name to a Slack channel ID."""
    # Check explicit map first
    if name in channel_map:
        return channel_map[name]
    # Check env var pattern: SLACK_CHANNEL_NOTIFICATIONS=C0ABC123
    env_key = f"SLACK_CHANNEL_{name.upper().replace('-', '_')}"
    env_val = os.environ.get(env_key, "")
    if env_val:
        return env_val
    # Fall back to notification channel
    return notification_channel

with open(reminders_file) as f:
    reminders = json.load(f)

now = datetime.now()
fired = 0
changed = False

for r in reminders:
    if r["status"] != "pending":
        continue
    try:
        remind_at = datetime.strptime(r["datetime"], "%Y-%m-%d %H:%M")
    except ValueError:
        continue

    if now >= remind_at:
        channel_id = resolve_channel(r.get("channel", "notifications"))
        if not channel_id or not slack_token:
            print(f"Cannot deliver reminder {r['id']}: missing channel ID or Slack token", file=sys.stderr)
            continue

        text = f"[Reminder] {r['message']}"
        payload = json.dumps({"channel": channel_id, "text": text})
        result = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
             "-H", f"Authorization: Bearer {slack_token}",
             "-H", "Content-Type: application/json",
             "-d", payload],
            capture_output=True, text=True
        )

        resp = json.loads(result.stdout) if result.stdout else {}
        if resp.get("ok"):
            r["status"] = "delivered"
            r["delivered_at"] = now.strftime("%Y-%m-%d %H:%M")
            fired += 1
            changed = True
            print(f"Fired reminder {r['id']}: {r['message']}")
        else:
            print(f"Failed to deliver reminder {r['id']}: {resp.get('error', 'unknown')}", file=sys.stderr)

if changed:
    with open(reminders_file, "w") as f:
        json.dump(reminders, f, indent=2)

if fired > 0:
    print(f"Fired {fired} reminder(s).")
PYEOF
    ;;

  remove)
    ID="${2:-}"
    if [[ -z "$ID" ]]; then
      echo "Usage: reminder.sh remove <id>" >&2
      exit 1
    fi
    python3 - "$ID" "$REMINDERS_FILE" <<'PYEOF'
import json, sys

target_id, reminders_file = sys.argv[1], sys.argv[2]

with open(reminders_file) as f:
    reminders = json.load(f)

original_count = len(reminders)
reminders = [r for r in reminders if r["id"] != target_id]

if len(reminders) == original_count:
    print(f"Reminder '{target_id}' not found.")
    sys.exit(1)

with open(reminders_file, "w") as f:
    json.dump(reminders, f, indent=2)

print(f"Reminder '{target_id}' removed.")
PYEOF
    ;;

  help|*)
    echo "Agent reminder system — reliable one-shot reminders via Slack"
    echo ""
    echo "Commands:"
    echo "  add <datetime> <message> [channel]   Add a reminder (datetime: 'YYYY-MM-DD HH:MM')"
    echo "  list                                  List all pending reminders"
    echo "  check                                 Fire any due reminders (called by timer)"
    echo "  remove <id>                           Remove a reminder by ID"
    echo ""
    echo "Setup: Set SLACK_BOT_TOKEN and SLACK_NOTIFICATION_CHANNEL in ~/.agent/.env"
    echo "Timer: systemd timer running 'reminder.sh check' every 5 minutes"
    ;;
esac
