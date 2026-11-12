#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d /private/tmp/clockin-launchd-test.XXXXXX)"
label="local.clockin.reminder.verification.$$"
service="gui/$(id -u)/$label"
loaded=false
cleanup() {
    if $loaded; then /bin/launchctl bootout "$service" >/dev/null 2>&1 || true; fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
/usr/bin/ditto "$project_dir/dist/ClockInReminder.app" "$test_dir/ClockInReminder.app"
mkdir -p "$test_dir/logs"
binary="$test_dir/ClockInReminder.app/Contents/MacOS/ClockInReminder"
"$binary" --state-dir "$test_dir/state" --initialize
bash "$project_dir/write-agent.sh" "$test_dir/agent.plist" "$test_dir/ClockInReminder.app" "$test_dir/logs" "$label"
/usr/bin/plutil -insert ProgramArguments.3 -json '"--state-dir"' "$test_dir/agent.plist"
/usr/bin/plutil -insert ProgramArguments.4 -string "$test_dir/state" "$test_dir/agent.plist"
/usr/bin/plutil -insert ProgramArguments.5 -json '"--status"' "$test_dir/agent.plist"
/usr/bin/plutil -replace StartInterval -integer 15 "$test_dir/agent.plist"
/usr/bin/plutil -replace ThrottleInterval -integer 1 "$test_dir/agent.plist"
/bin/launchctl bootstrap "gui/$(id -u)" "$test_dir/agent.plist"
loaded=true
sleep 18
count="$(/usr/bin/grep -c '开始日期' "$test_dir/logs/agent.log")"
[[ "$count" -ge 2 ]]
/bin/launchctl bootout "$service"
loaded=false
echo "PASS launchd 启动、正常退出后定期重启、停止服务（运行 $count 次）"
