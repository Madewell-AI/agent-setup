#!/usr/bin/env bash
# Cron Job Manager — CLI for managing scheduled AI agent jobs
# Uses systemd user timers for reliable scheduling
#
# Usage:
#   manage.sh list                    — List all jobs
#   manage.sh install                 — Install/update all systemd timers from jobs.json
#   manage.sh enable <id>             — Enable a job
#   manage.sh disable <id>            — Disable a job
#   manage.sh run <id>                — Run a job immediately
#   manage.sh logs <id> [n]           — View last n run records
#   manage.sh add <id> <name> <schedule> <tz> <prompt> [workdir] [deliver]
#   manage.sh remove <id>             — Remove a job
#   manage.sh help                    — Show this help

set -euo pipefail

CRON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_FILE="${CRON_DIR}/jobs.json"
LOGS_DIR="${CRON_DIR}/logs"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
RUNNER="${CRON_DIR}/run-job.sh"

mkdir -p "$LOGS_DIR" "$SYSTEMD_DIR"

# Initialize jobs file if it doesn't exist
if [ ! -f "$JOBS_FILE" ]; then
    echo '{"jobs": []}' > "$JOBS_FILE"
fi

cmd="${1:-help}"

case "$cmd" in

  list)
    python3 - <<'PYEOF'
import json, os
jobs_file = os.path.expanduser(os.environ.get('JOBS_FILE', '')) or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'jobs.json')
PYEOF
    python3 -c "
import json
data = json.load(open('${JOBS_FILE}'))
jobs = data.get('jobs', data) if isinstance(data, dict) else data
if not jobs:
    print('No jobs configured.')
else:
    for j in jobs:
        status = 'enabled' if j.get('enabled', True) else 'disabled'
        print(f'  [{status}] {j[\"id\"]}')
        print(f'    Name:     {j[\"name\"]}')
        print(f'    Schedule: {j[\"schedule\"]} ({j.get(\"tz\", \"UTC\")})')
        print(f'    Deliver:  {j.get(\"deliver\", False)}')
        print()
"
    ;;

  install)
    # Ensure log directories exist for all jobs
    python3 -c "
import json, os
data = json.load(open('${JOBS_FILE}'))
jobs = data.get('jobs', data) if isinstance(data, dict) else data
for j in jobs:
    os.makedirs('${LOGS_DIR}/' + j['id'], exist_ok=True)
"

    # Remove stale agent-cron timers
    for f in "$SYSTEMD_DIR"/agent-cron-*.timer; do
        [[ -f "$f" ]] && rm -f "$f" && echo "Removed: $(basename "$f")"
    done

    python3 - <<'PYEOF'
import json, os, re

data = json.load(open(os.environ.get('JOBS_FILE', '') or '${JOBS_FILE}'))
jobs = data.get('jobs', data) if isinstance(data, dict) else data
systemd_dir = '${SYSTEMD_DIR}'

def cron_part_to_systemd(part):
    """Convert a single cron field (minute or hour) to systemd calendar syntax."""
    m = re.match(r'^\*/(\d+)$', part)
    if m:
        return f'0/{m.group(1)}'
    return part

DOW_MAP = {'0': 'Sun', '1': 'Mon', '2': 'Tue', '3': 'Wed', '4': 'Thu', '5': 'Fri', '6': 'Sat', '7': 'Sun'}

def cron_dow_to_systemd(dow):
    """Convert cron day-of-week to systemd format. e.g. 1-5 -> Mon..Fri, 0,6 -> Sun,Sat"""
    if dow == '*':
        return '*'
    m = re.match(r'^(\d)-(\d)$', dow)
    if m:
        return f'{DOW_MAP[m.group(1)]}..{DOW_MAP[m.group(2)]}'
    if ',' in dow:
        return ','.join(DOW_MAP.get(d, d) for d in dow.split(','))
    if dow in DOW_MAP:
        return DOW_MAP[dow]
    return dow

def cron_to_calendar(sched, tz):
    parts = sched.split()
    if len(parts) != 5:
        return sched
    minute, hour, dom, month, dow = parts
    if dom == '*' and month == '*':
        h = cron_part_to_systemd(hour)
        m = cron_part_to_systemd(minute)
        dow_sys = cron_dow_to_systemd(dow)
        if re.match(r'^\d+$', hour) and re.match(r'^\d+$', minute):
            if dow_sys == '*':
                return f'{hour.zfill(2)}:{minute.zfill(2)} {tz}'
            else:
                return f'{dow_sys} *-*-* {hour.zfill(2)}:{minute.zfill(2)}:00 {tz}'
        elif hour == '*' and re.match(r'^0/\d+$', m):
            if dow_sys == '*':
                return f'*:{m} {tz}'
            else:
                return f'{dow_sys} *-*-* *:{m}:00 {tz}'
        else:
            if dow_sys == '*':
                return f'*-*-* {h}:{m}:00 {tz}'
            else:
                return f'{dow_sys} *-*-* {h}:{m}:00 {tz}'
    return sched

cron_dir = '${CRON_DIR}'

for j in jobs:
    jid = j['id']
    tz = j.get('tz', 'UTC')
    calendar = cron_to_calendar(j['schedule'], tz)

    timer = f"""[Unit]
Description=Agent cron timer: {jid}

[Timer]
OnCalendar={calendar}
Persistent=true
Unit=agent-cron@{jid}.service

[Install]
WantedBy=timers.target
"""
    # Service unit
    service = f"""[Unit]
Description=Agent Cron: {j['name']}

[Service]
Type=oneshot
ExecStart={cron_dir}/run-job.sh {jid}
Environment=HOME={os.environ['HOME']}
"""
    timer_path = os.path.join(systemd_dir, f'agent-cron-{jid}.timer')
    service_path = os.path.join(systemd_dir, f'agent-cron@{jid}.service')
    with open(timer_path, 'w') as f:
        f.write(timer)
    with open(service_path, 'w') as f:
        f.write(service)
    print(f'Written: agent-cron-{jid}.timer')
PYEOF

    systemctl --user daemon-reload

    python3 -c "
import json, subprocess
data = json.load(open('${JOBS_FILE}'))
jobs = data.get('jobs', data) if isinstance(data, dict) else data
for j in jobs:
    jid = j['id']
    unit = f'agent-cron-{jid}.timer'
    if j.get('enabled', True):
        subprocess.run(['systemctl', '--user', 'enable', '--now', unit], capture_output=True)
        print(f'Enabled: {unit}')
    else:
        subprocess.run(['systemctl', '--user', 'disable', '--now', unit], capture_output=True)
        print(f'Disabled: {unit}')
"

    echo ""
    systemctl --user list-timers --no-pager | grep agent-cron || echo "(no agent-cron timers)"
    ;;

  add)
    ID="${2:-}"
    NAME="${3:-}"
    SCHEDULE="${4:-}"
    TZ="${5:-UTC}"
    PROMPT="${6:-}"
    WORKDIR="${7:-$HOME}"
    DELIVER="${8:-false}"

    if [[ -z "$ID" || -z "$NAME" || -z "$SCHEDULE" || -z "$PROMPT" ]]; then
        echo "Usage: manage.sh add <id> <name> <schedule> <tz> <prompt> [workdir] [deliver]"
        exit 1
    fi

    python3 - <<PYEOF
import json
data = json.load(open('${JOBS_FILE}'))
if isinstance(data, list):
    data = {"jobs": data}
if any(j['id'] == '$ID' for j in data['jobs']):
    print(f"Job '$ID' already exists.")
    exit(1)
data['jobs'].append({
    "id": "$ID",
    "name": "$NAME",
    "enabled": True,
    "schedule": "$SCHEDULE",
    "tz": "$TZ",
    "prompt": """$PROMPT""",
    "workdir": "$WORKDIR",
    "deliver": $( [[ "$DELIVER" == "true" ]] && echo "True" || echo "False" )
})
json.dump(data, open('${JOBS_FILE}', 'w'), indent=2)
print("Job '$ID' added. Run: manage.sh install")
PYEOF
    ;;

  remove)
    ID="${2:-}"
    [[ -z "$ID" ]] && echo "Usage: manage.sh remove <id>" && exit 1
    python3 - <<PYEOF
import json
data = json.load(open('${JOBS_FILE}'))
if isinstance(data, list):
    data = {"jobs": data}
before = len(data['jobs'])
data['jobs'] = [j for j in data['jobs'] if j['id'] != '$ID']
if len(data['jobs']) == before:
    print("Job '$ID' not found.")
    exit(1)
json.dump(data, open('${JOBS_FILE}', 'w'), indent=2)
print("Job '$ID' removed. Run: manage.sh install")
PYEOF
    ;;

  enable|disable)
    ID="${2:-}"
    [[ -z "$ID" ]] && echo "Usage: manage.sh $cmd <id>" && exit 1
    ENABLED=$( [[ "$cmd" == "enable" ]] && echo "True" || echo "False" )
    python3 - <<PYEOF
import json
data = json.load(open('${JOBS_FILE}'))
if isinstance(data, list):
    data = {"jobs": data}
matched = False
for j in data['jobs']:
    if j['id'] == '$ID':
        j['enabled'] = $ENABLED
        matched = True
if not matched:
    print("Job '$ID' not found.")
    exit(1)
json.dump(data, open('${JOBS_FILE}', 'w'), indent=2)
print("Job '$ID' set to $cmd. Run: manage.sh install")
PYEOF
    ;;

  run)
    ID="${2:-}"
    [[ -z "$ID" ]] && echo "Usage: manage.sh run <id>" && exit 1
    exec /bin/bash "$RUNNER" "$ID"
    ;;

  logs)
    ID="${2:-}"
    N="${3:-5}"
    [[ -z "$ID" ]] && echo "Usage: manage.sh logs <id> [n]" && exit 1
    LOG_DIR="${LOGS_DIR}/${ID}"
    RUNS_FILE="${LOG_DIR}/runs.jsonl"
    if [[ ! -f "$RUNS_FILE" ]]; then
        echo "No runs found for '$ID'."
        exit 0
    fi
    echo "Last $N runs for '$ID':"
    tail -n "$N" "$RUNS_FILE" | python3 -c "
import json, sys
for line in sys.stdin:
    r = json.loads(line.strip())
    print(f\"  {r.get('ts', r.get('timestamp','?'))}  status={r.get('status','?')}  started={r.get('startedAt', r.get('timestamp','?'))}\")
    if 'logFile' in r:
        print(f\"    log: {r['logFile']}\")
"
    ;;

  help|*)
    echo "Agent cron manager"
    echo ""
    echo "Commands:"
    echo "  list                                        List all jobs"
    echo "  install                                     Sync jobs.json to systemd timers"
    echo "  add <id> <name> <schedule> <tz> <prompt>   Add a new job"
    echo "  remove <id>                                 Remove a job"
    echo "  enable <id>                                 Enable a job"
    echo "  disable <id>                                Disable a job"
    echo "  run <id>                                    Run a job immediately"
    echo "  logs <id> [n]                               Show last n run records"
    ;;

esac
