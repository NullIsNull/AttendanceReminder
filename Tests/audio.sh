#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/attendance-audio.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
app="$test_dir/AudioTests.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/reminder.wav" "$app/Contents/Resources/"
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" \
    -framework AppKit -framework CoreAudio "$project_dir/Sources/ReminderCore.swift" \
    "$project_dir/Sources/ReminderAudio.swift" "$project_dir/Tests/Audio/main.swift" \
    -o "$app/Contents/MacOS/ClockInReminder"
"$app/Contents/MacOS/ClockInReminder"
