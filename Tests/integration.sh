#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/attendance-install-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
target="$test_dir/home with spaces & 中文"
state="$target/Library/Application Support/ClockInReminder/confirmations.json"
prefs="$target/Library/Application Support/ClockInReminder/preferences.json"
app="$target/Applications/AttendanceReminder.app"
bash "$project_dir/install.sh" 10：10 20:05 --prebuilt --stage "$target"
[[ -x "$app/Contents/MacOS/ClockInReminder" ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$app/Contents/Info.plist")" == true ]]
[[ "$(/usr/bin/plutil -extract morning raw -o - "$prefs")" == 10:10 ]]
[[ "$(/usr/bin/plutil -extract evening raw -o - "$prefs")" == 20:05 ]]
[[ ! -e "$target/Library/LaunchAgents/local.clockin.reminder.plist" ]]
/usr/bin/codesign --verify --strict "$app"
cmp "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE"
cp "$state" "$test_dir/expected-state.json"
cp "$prefs" "$test_dir/expected-prefs.json"
bash "$project_dir/install.sh" --prebuilt --stage "$target"
cmp "$state" "$test_dir/expected-state.json"
cmp "$prefs" "$test_dir/expected-prefs.json"
if bash "$project_dir/install.sh" 24:00 --prebuilt --stage "$target" >"$test_dir/invalid.log" 2>&1; then exit 1; fi
cmp "$prefs" "$test_dir/expected-prefs.json"
bash "$project_dir/uninstall.sh" --stage "$target"
[[ ! -e "$app" && -f "$state" && -f "$prefs" ]]
bash "$project_dir/install.sh" --prebuilt --stage "$target"
cmp "$state" "$test_dir/expected-state.json"
cmp "$prefs" "$test_dir/expected-prefs.json"
bash "$project_dir/uninstall.sh" --purge --stage "$target"
[[ ! -e "$app" && ! -e "$state" && ! -e "$prefs" ]]
echo "PASS 安装、LSUIElement、设置持久化、更新保留设置和记录、卸载和重装"
