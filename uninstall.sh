#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

target_root="$HOME"
staging=false
purge=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) purge=true; shift ;;
        --stage)
            [[ $# -ge 2 && "$2" == /* && "$2" != / && "$2" != "$HOME" ]] || {
                echo "--stage 需要独立的绝对目录。" >&2; exit 2;
            }
            target_root="$2"; staging=true; shift 2 ;;
        *) echo "用法：bash uninstall.sh [--purge] [--stage /absolute/test-directory]" >&2; exit 2 ;;
    esac
done
if [[ "$(id -u)" == 0 ]]; then echo "以安装时的用户运行，不使用 sudo。" >&2; exit 1; fi
label=local.clockin.reminder
app="$target_root/Applications/ClockInReminder.app"
plist="$target_root/Library/LaunchAgents/$label.plist"
state_dir="$target_root/Library/Application Support/ClockInReminder"
log_dir="$target_root/Library/Logs/ClockInReminder"
if ! $staging && /bin/launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$(id -u)/$label"
fi
# 仅结束安装路径中的实例，保留其他目录运行的演示或开发程序。
if ! $staging; then
    while read -r pid process_path; do
        if [[ "$process_path" == "$app/Contents/MacOS/ClockInReminder" ]]; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done < <(/bin/ps -U "$(id -u)" -o pid=,comm=)
fi
if [[ -e "$app" && ! -L "$app" ]]; then
    existing_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
    [[ "$existing_id" == "$label" ]] || { echo "目标不是打卡提醒程序，已停止删除：$app" >&2; exit 1; }
fi
rm -f -- "$plist"
rm -rf -- "$app"
if $purge; then
    rm -rf -- "$state_dir" "$log_dir"
    echo "已卸载，并删除本机确认记录及日志。"
else
    echo "已卸载。确认记录保留在：$state_dir"
fi
