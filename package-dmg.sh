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
# 直接生成 HFS+ 文件，再压缩成 DMG，打包时无需挂载临时磁盘。
/usr/bin/hdiutil makehybrid -hfs -hfs-volume-name AttendanceReminder \
    -hfs-openfolder "$content" -o "$stage/uncompressed.dmg" "$content"
/usr/bin/hdiutil convert "$stage/uncompressed.dmg" -format UDZO -ov -o "$output"
/usr/bin/hdiutil verify "$output"
echo "已生成：$output"
