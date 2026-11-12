#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
binary="$project_dir/dist/ClockInReminder.app/Contents/MacOS/ClockInReminder"
[[ "$("$binary" --validate-times)" == '10:00 19:10' ]]
[[ "$("$binary" 10:10 --validate-times)" == '10:10 19:10' ]]
[[ "$("$binary" 9：08 20:05 --validate-times)" == '09:08 20:05' ]]
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/clockin-cli-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
for invalid in 24:00 10:60 bad 10:1; do
    if "$binary" "$invalid" --state-dir "$test_dir/state" --initialize >"$test_dir/result" 2>&1; then
        echo "FAIL 非法参数被接受：$invalid" >&2; exit 1
    else
        [[ $? == 2 ]]
    fi
    [[ ! -e "$test_dir/state" ]]
done
if "$binary" 10:10 19:10 20:00 --validate-times >"$test_dir/result" 2>&1; then
    echo "FAIL 多余参数被接受" >&2; exit 1
fi
echo "PASS 命令行默认值、单参数、双参数、中文冒号、非法参数拒绝且不写状态"
