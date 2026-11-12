#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
umask 077

project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "此程序只能在 macOS 上编译。" >&2
    exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    echo "缺少 Apple 命令行工具。运行 xcode-select --install，安装后重试。" >&2
    exit 1
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/clockin-build.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
app="$build_dir/AttendanceReminder.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$project_dir/dist"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/reminder.wav" "$app/Contents/Resources/reminder.wav"
cp "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE"
mkdir -p "$app/Contents/Resources/Support"
cp "$project_dir/README.md" "$project_dir/LICENSE" "$project_dir/uninstall.sh" "$app/Contents/Resources/Support/"
/usr/bin/ditto "$project_dir/docs" "$app/Contents/Resources/Support/docs"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
/usr/bin/xcrun swiftc -O -module-cache-path "$build_dir/cache" \
    "$project_dir/Tools/GenerateIcon.swift" -o "$build_dir/GenerateIcon"
"$build_dir/GenerateIcon" "$build_dir/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
    echo "编译 ${arch}…"
    /usr/bin/xcrun swiftc -O -swift-version 5 -sdk "$sdk" \
        -target "$arch-apple-macos13.0" -module-cache-path "$build_dir/cache" \
        -framework AppKit -framework ServiceManagement "$project_dir/Sources/"*.swift \
        -o "$build_dir/ClockInReminder-$arch"
done
/usr/bin/lipo -create "$build_dir/ClockInReminder-arm64" "$build_dir/ClockInReminder-x86_64" \
    -output "$app/Contents/MacOS/ClockInReminder"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
rm -rf -- "$project_dir/dist/AttendanceReminder.app"
/usr/bin/ditto "$app" "$project_dir/dist/AttendanceReminder.app"
echo "已生成：$project_dir/dist/AttendanceReminder.app"
