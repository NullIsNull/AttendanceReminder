# AttendanceReminder

原生 Swift/AppKit 菜单栏打卡提醒程序，支持 macOS 13 及以上、Apple Silicon 和 Intel。默认在周一至周五本地时间 **10:00、19:10** 提醒，时间和声音可在设置窗口修改。

## DMG 安装

从 [Releases](https://github.com/NullIsNull/AttendanceReminder/releases/latest) 下载 DMG 安装包。

1. 打开 `AttendanceReminder-2.1.4.dmg`。
2. 把 `AttendanceReminder` 拖入 `Applications`（应用程序）。
3. 从“应用程序”打开，设置上下班时间、音效和最大音量，点击“保存设置”。
4. 需要登录后自动运行时，开启“登录 Mac 时自动启动”。

应用只显示右上角菜单栏图标，Dock 不显示图标。再次打开应用或点击菜单栏“设置…”可修改设置。安装后可推出 DMG。

安装包采用本地临时签名，未做 Apple Developer ID 签名或公证。首次打开可能被 macOS 拦截；确认文件来源后，可在“系统设置 → 隐私与安全性”中允许打开。不需要关闭系统安全检查。没有 DMG 时可按下文从源码构建。

安装盘只显示应用和“应用程序”入口。使用说明保留在仓库和应用包内。

macOS 26 及以上采用原生 Liquid Glass；较早系统使用磨砂材质。外观跟随系统明暗设置，开启“减少透明度”时使用实色面板。

## 功能

- 多显示器置顶提醒窗口，最大 1400×900，标题、时间和确认按钮放大；完成公司考勤后点击“已打卡”，保存成功才关闭当前提醒。
- 每 30 秒提示一次，支持 5 种系统音效、内置铃声、静音、试听和最大音量；可逐次渐强。
- 睡眠唤醒、重新打开后补出遗漏项；已确认项在重启后不重复；修改并保存某一时段的时间，会重新提醒该时段。
- 暂停 15 分钟、立即恢复、紧急退出；登录启动使用 macOS 原生登录项。
- 上班、下班分别统计确认次数和待办，可单独确认；设置打开时新到点仍自动弹窗。
- 系统静音或音量为 0 时显示提示；试听与正式提醒互不打断。
- 设置和确认记录保存在本机，不联网。

**点击“已打卡”只保存本机确认，不会向公司考勤系统提交打卡。**

[使用说明](docs/使用说明.md) 包含声音、暂停、旧版升级和图形卸载步骤。[运行规则](docs/BEHAVIOR.md) 说明补提醒、时区和持久化；[故障排查](docs/TROUBLESHOOTING.md) 说明启动、声音和记录问题；[验证记录](docs/VERIFICATION.md) 列出已验证结果和未实测场景。

## 从源码构建

构建需要带 macOS 26 或更新 SDK 的 Apple Command Line Tools，运行仍支持 macOS 13 及以上。缺少工具时执行 `xcode-select --install`。在 macOS 终端运行：

```bash
git clone --branch v2.1.4 git@github.com:NullIsNull/AttendanceReminder.git
cd AttendanceReminder
bash test.sh
bash build.sh
bash Tests/cli.sh
bash Tests/integration.sh
bash package-dmg.sh --no-build
```

打包需要系统磁盘镜像服务；脚本会挂载最终 DMG，检查应用复制前后的签名、中文文件名和内容。任一步失败即停止，不输出发布包。

产物为 `dist/AttendanceReminder.app` 和 `dist/AttendanceReminder-2.1.4.dmg`。源码使用 GPL-3.0-only，完整许可证见 [LICENSE](LICENSE)。图标、脚本、文档和自带生成音效适用同一许可证；macOS 系统音效不包含在仓库中。

开发者仍可使用 `bash install.sh [上班时间] [下班时间] --prebuilt` 安装到 `~/Applications`，以及 `bash uninstall.sh` 卸载。脚本不自动修改登录启动；日常使用通过 DMG 和设置界面完成。
