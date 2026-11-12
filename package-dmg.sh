#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if [[ "${1:-}" != --no-build ]]; then /bin/bash "$project_dir/build.sh"; fi
app="$project_dir/dist/AttendanceReminder.app"
/usr/bin/codesign --verify --strict "$app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/attendance-dmg.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
content="$stage/content"
mkdir -p "$content"
/usr/bin/ditto "$app" "$content/AttendanceReminder.app"
ln -s /Applications "$content/Applications"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
output="$project_dir/dist/AttendanceReminder-$version.dmg"
# makehybrid 会给资源文件写入 FinderInfo，导致挂载后的签名校验失败。
/usr/bin/hdiutil create -srcfolder "$content" -volname AttendanceReminder \
    -fs HFS+ -format UDZO -ov "$stage/AttendanceReminder.dmg"
/bin/bash "$project_dir/Tests/dmg.sh" "$stage/AttendanceReminder.dmg" "$app"
/bin/mv -f "$stage/AttendanceReminder.dmg" "$output"
echo "已生成：$output"
