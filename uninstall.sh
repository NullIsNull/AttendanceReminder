#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
root="$HOME"
staging=false
purge=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) purge=true; shift ;;
        --stage)
            [[ $# -ge 2 && "$2" == /* && "$2" != / && "$2" != "$HOME" ]] || exit 2
            root="$2"; staging=true; shift 2 ;;
        *) echo "用法：bash uninstall.sh [--purge] [--stage /absolute/path]" >&2; exit 2 ;;
    esac
done
app="$root/Applications/AttendanceReminder.app"
if ! $staging && [[ ! -e "$app" && -e /Applications/AttendanceReminder.app ]]; then app=/Applications/AttendanceReminder.app; fi
if [[ -e "$app" && ! -L "$app" ]]; then
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" == local.clockin.reminder ]] || exit 1
    if ! $staging; then
        "$app/Contents/MacOS/ClockInReminder" --disable-login
        while read -r pid process_path; do
            if [[ "$process_path" == "$app/Contents/MacOS/ClockInReminder" ]]; then kill -TERM "$pid"; fi
        done < <(/bin/ps -U "$(id -u)" -o pid=,comm=)
    fi
fi
rm -rf -- "$app"
if $purge; then
    rm -rf -- "$root/Library/Application Support/ClockInReminder" "$root/Library/Logs/ClockInReminder"
    echo "已卸载并删除本机记录。"
else
    echo "已卸载，打卡确认和设置保留。"
fi
