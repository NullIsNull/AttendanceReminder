#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
umask 077
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
target_root="$HOME"
staging=false
prebuilt=false
morning=10:00
evening=19:10
time_count=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prebuilt) prebuilt=true; shift ;;
        --stage)
            [[ $# -ge 2 && "$2" == /* && "$2" != / && "$2" != "$HOME" ]] || exit 2
            target_root="$2"; staging=true; shift 2 ;;
        -*) echo "用法：bash install.sh [上班时间] [下班时间] [--prebuilt] [--stage /absolute/path]" >&2; exit 2 ;;
        *)
            if (( time_count == 0 )); then morning="$1";
            elif (( time_count == 1 )); then evening="$1";
            else echo "最多两个时间参数。" >&2; exit 2; fi
            time_count=$((time_count + 1)); shift ;;
    esac
done
[[ "$(id -u)" != 0 ]] || { echo "不使用 sudo。" >&2; exit 1; }
if ! $prebuilt; then /bin/bash "$project_dir/build.sh"; fi
source_app="$project_dir/dist/AttendanceReminder.app"
/usr/bin/codesign --verify --strict "$source_app"
normalized="$("$source_app/Contents/MacOS/ClockInReminder" "$morning" "$evening" --validate-times)"
read -r morning evening <<< "$normalized"
app="$target_root/Applications/AttendanceReminder.app"
state_dir="$target_root/Library/Application Support/ClockInReminder"
[[ ! -L "$app" && ! -L "$state_dir" ]] || { echo "拒绝覆盖符号链接。" >&2; exit 1; }
if [[ -e "$app" ]]; then
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" == local.clockin.reminder ]] || exit 1
fi
mkdir -p "$target_root/Applications"
stage="$(mktemp -d "$target_root/Applications/.attendance-install.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
/usr/bin/ditto "$source_app" "$stage/AttendanceReminder.app"
"$source_app/Contents/MacOS/ClockInReminder" --state-dir "$state_dir" --initialize
if (( time_count > 0 )); then
    "$source_app/Contents/MacOS/ClockInReminder" "$morning" "$evening" --state-dir "$state_dir" --configure
fi
if [[ -e "$app" ]]; then mv "$app" "$stage/previous.app"; fi
if ! mv "$stage/AttendanceReminder.app" "$app"; then
    if [[ -e "$stage/previous.app" ]]; then mv "$stage/previous.app" "$app"; fi
    exit 1
fi
if $staging; then
    echo "隔离安装完成；未修改系统登录项。"
else
    /usr/bin/open "$app" --args --settings
    echo "已安装。登录启动请在应用的设置窗口中开启。"
fi
