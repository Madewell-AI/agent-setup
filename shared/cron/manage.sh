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
#   manage.sh logs <id> [--tail N]    — View job logs
#   manage.sh add <json>              — Add a new job
#   manage.sh remove <id>             — Remove a job

set -euo pipefail

CRON_DIR="${HOME}/.agent/cron"
JOBS_FILE="${CRON_DIR}/jobs.json"
LOGS_DIR="${CRON_DIR}/logs"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

mkdir -p "$CRON_DIR" "$LOGS_DIR" "$SYSTEMD_DIR"

# Initialize jobs file if it doesn't exist
if [ ! -f "$JOBS_FILE" ]; then
    echo "[]" > "$JOBS_FILE"
fi

cmd_list() {
    echo "=== Scheduled Jobs ==="
    python3 -c "
import json
with open('${JOBS_FILE}') as f:
    jobs = json.load(f)
for j in jobs:
    status = 'ENABLED' if j.get('enabled', False) else 'disabled'
    print(f\"  [{status}] {j['id']}: {j['name']} ({j['schedule']})\")
if not jobs:
    print('  No jobs configured. Copy jobs.example.json to jobs.json to get started.')
"
}

cmd_install() {
    echo "Installing systemd timers..."

    python3 -c "
import json, os

jobs_file = '${JOBS_FILE}'
systemd_dir = '${SYSTEMD_DIR}'
cron_dir = '${CRON_DIR}'

with open(jobs_file) as f:
    jobs = json.load(f)

for job in jobs:
    job_id = job['id']
    schedule = job['schedule']
    tz = job.get('tz', 'UTC')

    # Convert cron to OnCalendar format (simplified)
    # For complex schedules, use the cron expression with systemd-cron-next
    parts = schedule.split()
    if len(parts) == 5:
        minute, hour, dom, month, dow = parts

    # Create service unit
    service = f'''[Unit]
Description=Agent Cron: {job['name']}

[Service]
Type=oneshot
ExecStart={cron_dir}/run-job.sh {job_id}
Environment=HOME={os.environ['HOME']}
'''
    service_path = os.path.join(systemd_dir, f'agent-cron@{job_id}.service')
    with open(service_path, 'w') as f:
        f.write(service)

    # Create timer unit
    timer = f'''[Unit]
Description=Timer for Agent Cron: {job['name']}

[Timer]
OnCalendar={schedule}
Persistent=true

[Install]
WantedBy=timers.target
'''
    timer_path = os.path.join(systemd_dir, f'agent-cron@{job_id}.timer')
    with open(timer_path, 'w') as f:
        f.write(timer)

    print(f'  Created timer for: {job_id}')
"

    systemctl --user daemon-reload

    # Enable/disable timers based on job config
    python3 -c "
import json, subprocess
with open('${JOBS_FILE}') as f:
    jobs = json.load(f)
for job in jobs:
    timer = f\"agent-cron@{job['id']}.timer\"
    if job.get('enabled', False):
        subprocess.run(['systemctl', '--user', 'enable', '--now', timer], capture_output=True)
        print(f'  Enabled: {job[\"id\"]}')
    else:
        subprocess.run(['systemctl', '--user', 'disable', '--now', timer], capture_output=True)
        print(f'  Disabled: {job[\"id\"]}')
"
    echo "Done."
}

cmd_enable() {
    local job_id="${1:?Usage: manage.sh enable <job-id>}"
    python3 -c "
import json
with open('${JOBS_FILE}', 'r+') as f:
    jobs = json.load(f)
    for j in jobs:
        if j['id'] == '${job_id}':
            j['enabled'] = True
            break
    else:
        print(f'Job not found: ${job_id}')
        exit(1)
    f.seek(0)
    json.dump(jobs, f, indent=2)
    f.truncate()
print(f'Enabled: ${job_id}')
"
    systemctl --user enable --now "agent-cron@${job_id}.timer" 2>/dev/null || true
}

cmd_disable() {
    local job_id="${1:?Usage: manage.sh disable <job-id>}"
    python3 -c "
import json
with open('${JOBS_FILE}', 'r+') as f:
    jobs = json.load(f)
    for j in jobs:
        if j['id'] == '${job_id}':
            j['enabled'] = False
            break
    f.seek(0)
    json.dump(jobs, f, indent=2)
    f.truncate()
print(f'Disabled: ${job_id}')
"
    systemctl --user disable --now "agent-cron@${job_id}.timer" 2>/dev/null || true
}

cmd_run() {
    local job_id="${1:?Usage: manage.sh run <job-id>}"
    echo "Running job: ${job_id}"
    "${CRON_DIR}/run-job.sh" "$job_id"
}

cmd_logs() {
    local job_id="${1:?Usage: manage.sh logs <job-id>}"
    local tail_n="${2:-20}"
    local log_dir="${LOGS_DIR}/${job_id}"

    if [ ! -d "$log_dir" ]; then
        echo "No logs for: ${job_id}"
        exit 0
    fi

    echo "=== Recent runs for: ${job_id} ==="
    ls -t "$log_dir"/*.log 2>/dev/null | head -5 | while read logfile; do
        echo "--- $(basename "$logfile") ---"
        tail -"$tail_n" "$logfile"
        echo ""
    done
}

# Route command
case "${1:-list}" in
    list)    cmd_list ;;
    install) cmd_install ;;
    enable)  cmd_enable "${2:-}" ;;
    disable) cmd_disable "${2:-}" ;;
    run)     cmd_run "${2:-}" ;;
    logs)    cmd_logs "${2:-}" "${3:-20}" ;;
    *)       echo "Usage: manage.sh {list|install|enable|disable|run|logs} [args]" ;;
esac
