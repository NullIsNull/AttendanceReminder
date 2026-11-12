#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
umask 077

project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
target_root="$HOME"
staging=false
prebuilt=false
morning_time=10:00
evening_time=19:10
time_count=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prebuilt) prebuilt=true; shift ;;
        --stage)
            [[ $# -ge 2 && "$2" == /* && "$2" != / && "$2" != "$HOME" ]] || {
                echo "--stage 需要一个独立的绝对目录。" >&2; exit 2;
            }
            target_root="$2"; staging=true; shift 2 ;;
        -*) echo "用法：bash install.sh [上班时间] [下班时间] [--prebuilt] [--stage /absolute/test-directory]" >&2; exit 2 ;;
        *)
            if (( time_count == 0 )); then morning_time="$1";
            elif (( time_count == 1 )); then evening_time="$1";
            else echo "最多提供两个时间参数。" >&2; exit 2; fi
            time_count=$((time_count + 1)); shift ;;
    esac
done
if [[ "$(id -u)" == 0 ]]; then echo "以当前登录用户运行，不使用 sudo。" >&2; exit 1; fi
if [[ "$(uname -s)" != Darwin ]]; then echo "仅支持 macOS。" >&2; exit 1; fi
if ! $staging; then /bin/launchctl print "gui/$(id -u)" >/dev/null; fi
if ! $prebuilt; then /bin/bash "$project_dir/build.sh"; fi

source_app="$project_dir/dist/ClockInReminder.app"
if [[ ! -x "$source_app/Contents/MacOS/ClockInReminder" ]]; then
    echo "找不到可安装程序，先运行 bash build.sh。" >&2; exit 1
fi
/usr/bin/codesign --verify --strict "$source_app"
normalized_times="$("$source_app/Contents/MacOS/ClockInReminder" "$morning_time" "$evening_time" --validate-times)"
read -r morning_time evening_time <<< "$normalized_times"
label=local.clockin.reminder
app="$target_root/Applications/ClockInReminder.app"
plist="$target_root/Library/LaunchAgents/$label.plist"
state_dir="$target_root/Library/Application Support/ClockInReminder"
log_dir="$target_root/Library/Logs/ClockInReminder"
for path in "$app" "$plist" "$state_dir" "$log_dir"; do
    if [[ -L "$path" ]]; then echo "拒绝覆盖符号链接：$path" >&2; exit 1; fi
done
if [[ -e "$app" ]]; then
    existing_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
    [[ "$existing_id" == "$label" ]] || { echo "目标目录已有其他程序：$app" >&2; exit 1; }
fi
mkdir -p "$target_root/Applications" "$(dirname "$plist")" "$state_dir" "$log_dir"
chmod 700 "$state_dir" "$log_dir"
stage_dir="$(mktemp -d "$target_root/Applications/.clockin-install.XXXXXX")"
was_loaded=false
swapped=false
completed=false
cleanup() {
    result=$?
    if ! $completed; then
        if $swapped; then
            if ! $staging; then /bin/launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true; fi
            rm -rf -- "$app"
            rm -f -- "$plist"
            if [[ -e "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$app"; fi
            if [[ -e "$stage_dir/previous.plist" ]]; then mv "$stage_dir/previous.plist" "$plist"; fi
        fi
        if $was_loaded; then
            /bin/launchctl bootstrap "gui/$(id -u)" "$plist" || echo "旧服务恢复失败，请按 README 重新安装。" >&2
        fi
    fi
    rm -rf -- "$stage_dir"
    exit "$result"
}
trap cleanup EXIT
/usr/bin/ditto "$source_app" "$stage_dir/ClockInReminder.app"
/bin/bash "$project_dir/write-agent.sh" "$stage_dir/agent.plist" "$app" "$log_dir" "$label" "$morning_time" "$evening_time"
mkdir -p "$stage_dir/ClockInReminder.app/Contents/Resources/Support"
cp "$project_dir/uninstall.sh" "$stage_dir/ClockInReminder.app/Contents/Resources/Support/uninstall.sh"
cp "$project_dir/README.md" "$stage_dir/ClockInReminder.app/Contents/Resources/Support/README.md"
cp "$project_dir/LICENSE" "$stage_dir/ClockInReminder.app/Contents/Resources/Support/LICENSE"
if [[ -d "$project_dir/docs" ]]; then
    /usr/bin/ditto "$project_dir/docs" "$stage_dir/ClockInReminder.app/Contents/Resources/Support/docs"
fi
/usr/bin/codesign --force --sign - "$stage_dir/ClockInReminder.app"
/usr/bin/codesign --verify --strict "$stage_dir/ClockInReminder.app"

if ! $staging && /bin/launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$(id -u)/$label"
    was_loaded=true
    sleep 1
fi
# 初始化失败时保留旧程序和原记录，不用空文件覆盖历史确认。
"$stage_dir/ClockInReminder.app/Contents/MacOS/ClockInReminder" --state-dir "$state_dir" --initialize
if [[ -e "$plist" ]]; then cp "$plist" "$stage_dir/previous.plist"; fi
if [[ -e "$app" ]]; then mv "$app" "$stage_dir/previous.app"; fi
swapped=true
mv "$stage_dir/ClockInReminder.app" "$app"
mv "$stage_dir/agent.plist" "$plist"
chmod 600 "$plist"
if $staging; then
    completed=true
    echo "隔离安装完成：${target_root}（未注册后台服务）"
    exit 0
fi
/bin/launchctl enable "gui/$(id -u)/$label"
if ! /bin/launchctl bootstrap "gui/$(id -u)" "$plist"; then
    echo "后台服务启动失败，正在恢复安装前的程序文件。" >&2
    exit 1
fi
sleep 2
if ! /bin/launchctl print "gui/$(id -u)/$label" >/dev/null; then
    echo "后台服务未注册成功。查看 $log_dir/agent-error.log" >&2; exit 1
fi
completed=true
echo "安装完成。菜单栏会显示“打卡”；紧急暂停期间暂不显示。"
echo "工作日 ${morning_time}、${evening_time} 使用 Mac 本地时间；今天已错过的时间会立即补提醒。"
echo "卸载：bash \"$app/Contents/Resources/Support/uninstall.sh\""
