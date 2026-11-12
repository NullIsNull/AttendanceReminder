#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/clockin-install-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
target="$test_dir/home with spaces & 中文"
state="$target/Library/Application Support/ClockInReminder/confirmations.json"
plist="$target/Library/LaunchAgents/local.clockin.reminder.plist"
bash "$project_dir/install.sh" --prebuilt --stage "$target"
[[ -x "$target/Applications/ClockInReminder.app/Contents/MacOS/ClockInReminder" ]]
[[ "$(/usr/bin/plutil -extract Label raw -o - "$plist")" == local.clockin.reminder ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist")" == "$target/Applications/ClockInReminder.app/Contents/MacOS/ClockInReminder" ]]
[[ "$(/usr/bin/plutil -extract StartInterval raw -o - "$plist")" == 60 ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$plist")" == 10:00 ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "$plist")" == 19:10 ]]
[[ "$(/usr/bin/plutil -extract StartCalendarInterval.9.Weekday raw -o - "$plist")" == 5 ]]
[[ "$(/usr/bin/plutil -extract StartCalendarInterval.9.Hour raw -o - "$plist")" == 19 ]]
[[ "$(/usr/bin/plutil -extract StartCalendarInterval.9.Minute raw -o - "$plist")" == 10 ]]
/usr/bin/codesign --verify --strict "$target/Applications/ClockInReminder.app"
cmp "$project_dir/LICENSE" "$target/Applications/ClockInReminder.app/Contents/Resources/LICENSE"
cmp "$project_dir/LICENSE" "$target/Applications/ClockInReminder.app/Contents/Resources/Support/LICENSE"
cat > "$state" <<'JSON'
{
  "version": 1,
  "firstDay": "2026-11-09",
  "createdAt": "2026-11-09T00:00:00Z",
  "confirmations": {
    "2026-11-09/morning": {
      "day": "2026-11-09", "slot": "morning", "scheduledAt": "2026-11-09T02:00:00Z",
      "confirmedAt": "2026-11-09T02:01:00Z", "timeZone": "Asia/Singapore"
    }
  }
}
JSON
cp "$state" "$test_dir/expected.json"
bash "$project_dir/install.sh" 10：10 20:05 --prebuilt --stage "$target"
[[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$plist")" == 10:10 ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "$plist")" == 20:05 ]]
for index in 0 2 4 6 8; do
    [[ "$(/usr/bin/plutil -extract "StartCalendarInterval.$index.Hour" raw -o - "$plist")" == 10 ]]
    [[ "$(/usr/bin/plutil -extract "StartCalendarInterval.$index.Minute" raw -o - "$plist")" == 10 ]]
done
for index in 1 3 5 7 9; do
    [[ "$(/usr/bin/plutil -extract "StartCalendarInterval.$index.Hour" raw -o - "$plist")" == 20 ]]
    [[ "$(/usr/bin/plutil -extract "StartCalendarInterval.$index.Minute" raw -o - "$plist")" == 5 ]]
done
cmp "$state" "$test_dir/expected.json"
cp "$plist" "$test_dir/expected.plist"
if bash "$project_dir/install.sh" 24:00 19:10 --prebuilt --stage "$target" >"$test_dir/invalid.log" 2>&1; then
    echo "FAIL 无效时间被接受" >&2; exit 1
fi
cmp "$plist" "$test_dir/expected.plist"
cmp "$state" "$test_dir/expected.json"
bash "$project_dir/uninstall.sh" --stage "$target"
[[ ! -e "$target/Applications/ClockInReminder.app" && ! -e "$plist" && -f "$state" ]]
cmp "$state" "$test_dir/expected.json"
bash "$project_dir/install.sh" 9:08 --prebuilt --stage "$target"
[[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$plist")" == 09:08 ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "$plist")" == 19:10 ]]
cmp "$state" "$test_dir/expected.json"
bash "$project_dir/uninstall.sh" --purge --stage "$target"
[[ ! -e "$target/Applications/ClockInReminder.app" && ! -e "$plist" && ! -e "$state" ]]
echo "PASS 隔离安装、特殊字符路径、默认及自定义时间、十个日历条目、无效参数拒绝、签名、更新保留记录、卸载和重装"
