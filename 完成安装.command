#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
finish() {
    result=$?
    if [[ "$result" -eq 0 ]]; then
        echo "安装完成：周一至周五 10:10、19:10，使用 Mac 本地时间。"
        echo "使用说明：$project_dir/docs/使用说明.md"
    else
        echo "安装未完成，请保留上面的错误信息。"
    fi
    if [[ -t 0 ]]; then read -r -p "按回车关闭此窗口。" || true; fi
    exit "$result"
}
trap finish EXIT

echo "安装打卡提醒：上班 10:10，下班 19:10。已有确认记录会保留。"
# 试运行副本占用写锁时，先结束同一安装包启动的进程。
while read -r pid process_path; do
    if [[ "$process_path" == "$project_dir/dist/ClockInReminder.app/Contents/MacOS/ClockInReminder" ]]; then
        kill -TERM "$pid"
        for attempt in 1 2 3 4 5; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 1
        done
    fi
done < <(/bin/ps -U "$(id -u)" -o pid=,comm=)

if [[ -x "$project_dir/dist/ClockInReminder.app/Contents/MacOS/ClockInReminder" ]]; then
    /bin/bash "$project_dir/install.sh" 10:10 19:10 --prebuilt
else
    /bin/bash "$project_dir/install.sh" 10:10 19:10
fi
/usr/bin/open "$project_dir/docs/使用说明.md"
