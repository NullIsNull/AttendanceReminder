#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

image="${1:?需要 DMG 路径}"
reference="${2:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/attendance-dmg-test.XXXXXX")"
mount="$work/mounted"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$mount"; then
            echo "卸载测试镜像失败，保留目录：$work" >&2
            return 1
        fi
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT

/usr/bin/hdiutil verify "$image"
mkdir "$mount"
/usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" "$image"
mounted=true
app="$mount/AttendanceReminder.app"
[[ -d "$app" && -L "$mount/Applications" ]]
[[ "$(readlink "$mount/Applications")" == /Applications ]]
entries=("$mount"/*)
[[ ${#entries[@]} == 2 ]]
/usr/bin/codesign --verify --strict "$app"
[[ -f "$app/Contents/Resources/Support/docs/使用说明.md" ]]

# 保留扩展属性复制，覆盖从安装盘复制后的签名问题。
copy="$work/copied/AttendanceReminder.app"
/usr/bin/ditto "$app" "$copy"
/usr/bin/codesign --verify --strict "$copy"
/usr/bin/diff -rq "$app" "$copy"
if [[ -n "$reference" ]]; then
    /usr/bin/diff -rq "$reference" "$copy"
fi
echo "DMG 挂载、根目录、中文文件名、复制前后签名及文件内容检查通过。"
