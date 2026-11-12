#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/clockin-check.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" \
    "$project_dir/Sources/ReminderCore.swift" "$project_dir/Tests/main.swift" -o "$test_dir/CoreTests"
"$test_dir/CoreTests"
for script in "$project_dir/"*.sh "$project_dir/Tests/"*.sh "$project_dir/"*.command; do /bin/bash -n "$script"; done
/usr/bin/plutil -lint "$project_dir/Resources/Info.plist"
echo "Shell 语法和 Info.plist 检查通过。"
