#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 && "$1" == /* ]] || { echo 'Usage: bash Tests/interface-preview.sh /absolute/output-directory settings|conflict|reminder|due|confirmed [dark]' >&2; exit 2; }
output="$1"
mode="$2"
case "$mode" in settings|conflict|reminder|due|confirmed) ;; *) exit 2 ;; esac
mkdir -p "$output"
app="$output/AttendancePreview-$mode.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/reminder.wav" "$app/Contents/Resources/"
/usr/bin/plutil -replace CFBundleIdentifier -string "local.attendance.uitest.$mode" "$app/Contents/Info.plist"
/usr/bin/plutil -insert TestStateDirectory -string "$output/state-$mode" "$app/Contents/Info.plist"
/usr/bin/plutil -insert TestMode -string "$mode" "$app/Contents/Info.plist"
if [[ "${3:-}" == dark ]]; then /usr/bin/plutil -insert TestDarkAppearance -bool true "$app/Contents/Info.plist"; fi
sources=()
for source in "$project_dir/Sources/"*.swift; do
    [[ "$source" == */main.swift ]] || sources+=("$source")
done
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$output/cache" \
    -target "$(uname -m)-apple-macos13.0" -framework AppKit -framework ServiceManagement \
    "${sources[@]}" "$project_dir/Tests/InterfacePreview/main.swift" -o "$app/Contents/MacOS/ClockInReminder"
/usr/bin/codesign --force --sign - "$app"
echo "$app"
