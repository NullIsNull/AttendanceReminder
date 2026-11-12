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
app="$build_dir/ClockInReminder.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$project_dir/dist"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/reminder.wav" "$app/Contents/Resources/reminder.wav"
cp "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
    echo "编译 ${arch}…"
    /usr/bin/xcrun swiftc -O -swift-version 5 -sdk "$sdk" \
        -target "$arch-apple-macos13.0" -module-cache-path "$build_dir/cache" \
        -framework AppKit "$project_dir/Sources/ReminderCore.swift" \
        "$project_dir/Sources/ReminderApplication.swift" "$project_dir/Sources/main.swift" \
        -o "$build_dir/ClockInReminder-$arch"
done
/usr/bin/lipo -create "$build_dir/ClockInReminder-arm64" "$build_dir/ClockInReminder-x86_64" \
    -output "$app/Contents/MacOS/ClockInReminder"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
rm -rf -- "$project_dir/dist/ClockInReminder.app"
/usr/bin/ditto "$app" "$project_dir/dist/ClockInReminder.app"
echo "已生成：$project_dir/dist/ClockInReminder.app"
