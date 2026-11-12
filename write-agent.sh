#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
umask 077

if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "用法：bash write-agent.sh PLIST APP_PATH LOG_DIR [LABEL [MORNING [EVENING]]]" >&2
    exit 2
fi
plist="$1"
app="$2"
log_dir="$3"
label="${4:-local.clockin.reminder}"
normalize_time() {
    local value="${1//：/:}"
    if [[ ! "$value" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
        echo "时间格式不正确：$1" >&2; return 2
    fi
    local hour=$((10#${BASH_REMATCH[1]}))
    local minute=$((10#${BASH_REMATCH[2]}))
    if (( hour > 23 || minute > 59 )); then echo "时间超出范围：$1" >&2; return 2; fi
    printf '%02d:%02d' "$hour" "$minute"
}
morning="$(normalize_time "${5:-10:00}")"
evening="$(normalize_time "${6:-19:10}")"
if [[ ! "$morning" < "$evening" ]]; then echo "上班时间须早于同一天的下班时间。" >&2; exit 2; fi
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert Label -string "$label" "$plist"
/usr/bin/plutil -insert ProgramArguments -array "$plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$app/Contents/MacOS/ClockInReminder" "$plist"
/usr/bin/plutil -insert ProgramArguments.1 -string "$morning" "$plist"
/usr/bin/plutil -insert ProgramArguments.2 -string "$evening" "$plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$plist"
/usr/bin/plutil -insert KeepAlive -dictionary "$plist"
/usr/bin/plutil -insert KeepAlive.SuccessfulExit -bool false "$plist"
/usr/bin/plutil -insert StartInterval -integer 60 "$plist"
/usr/bin/plutil -insert ThrottleInterval -integer 15 "$plist"
/usr/bin/plutil -insert ExitTimeOut -integer 5 "$plist"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$plist"
/usr/bin/plutil -insert ProcessType -string Interactive "$plist"
/usr/bin/plutil -insert StandardOutPath -string "$log_dir/agent.log" "$plist"
/usr/bin/plutil -insert StandardErrorPath -string "$log_dir/agent-error.log" "$plist"
/usr/bin/plutil -insert StartCalendarInterval -array "$plist"
entry=0
for weekday in 1 2 3 4 5; do
    for slot in morning evening; do
        time="$morning"
        if [[ "$slot" == evening ]]; then time="$evening"; fi
        hour=$((10#${time%:*}))
        minute=$((10#${time#*:}))
        /usr/bin/plutil -insert "StartCalendarInterval.$entry" -dictionary "$plist"
        /usr/bin/plutil -insert "StartCalendarInterval.$entry.Weekday" -integer "$weekday" "$plist"
        /usr/bin/plutil -insert "StartCalendarInterval.$entry.Hour" -integer "$hour" "$plist"
        /usr/bin/plutil -insert "StartCalendarInterval.$entry.Minute" -integer "$minute" "$plist"
        entry=$((entry + 1))
    done
done
chmod 600 "$plist"
/usr/bin/plutil -lint "$plist"
