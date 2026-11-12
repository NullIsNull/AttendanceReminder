# AttendanceReminder

原生 Swift/AppKit macOS 打卡提醒程序，使用 launchd 实现登录自启和退出后恢复。支持 macOS 13 及以上，Apple Silicon 和 Intel。

## 从源码安装

```bash
git clone git@github.com:NullIsNull/AttendanceReminder.git
cd AttendanceReminder
bash install.sh 10:10 19:10
```

需要 Apple Command Line Tools；缺少时运行 `xcode-select --install`。仓库不包含编译后的 `.app`，安装脚本会在本机编译。也可双击 `完成安装.command`，没有编译产物时会自动构建。

[软件使用说明](docs/使用说明.md) 包含日常操作、渐强声音、暂停、修改时间和卸载方法。

按上班 10:10、下班 19:10 安装，可直接双击 `完成安装.command`。这个入口保留确认记录并设置登录自启；安装失败时会保留错误信息。

工作日按 Mac 本地时间显示置顶大窗口，默认 **10:00、19:10**，可通过启动参数修改。每 30 秒播放一次提示音，音量依次为 20%、40%、60%、80%、100%，达到 100% 后保持。点击“已打卡”后保存本机确认；有其他遗漏项时继续显示下一项。确认全部待办后，程序留在菜单栏。

每条新提醒从 20% 开始。百分比是提示音自身音量，实际响度仍受 Mac 系统音量影响；程序不改变系统音量或静音状态。

**“已打卡”只表示你自行确认，程序不接入公司考勤系统。** 窗口可拖动，可移开后操作考勤页面。睡眠不会被打断，唤醒或重新登录后补提醒。

## 安装

构建后得到 Apple Silicon 和 Intel 通用程序。已验证的环境见 [验证记录](docs/VERIFICATION.md)。

1. 克隆仓库，或下载并解压源码。
2. 打开“终端”，输入 `cd `，把源码文件夹拖入终端，按回车。
3. 执行：

   ```bash
   bash install.sh
   ```

默认从源码编译后安装。如果提示缺少 Apple 命令行工具，执行 `xcode-select --install`，安装完成后重跑安装命令。不使用 `sudo`。

若之前双击试运行过程序，先从菜单栏选择紧急退出，再安装；否则单实例锁会阻止安装期间修改记录。安装后可按下文“提前恢复提醒”清除暂停。

菜单栏出现“打卡 0/2”表示程序已运行。首次启用会补出今天已经错过的时间，不追溯启用日期之前的提醒。再次安装会保留已有确认记录和紧急暂停。

已运行 `bash build.sh` 生成程序后，可以跳过再次编译：

```bash
bash install.sh --prebuilt
```

构建脚本使用本地临时签名，未做 Apple Developer ID 签名或公证。安装脚本不会关闭 Gatekeeper 或批量删除下载隔离属性。

## 自定义打卡时间

第一个时间参数为上班时间，第二个为下班时间。例如上班 10:10、下班 19:10：

```bash
dist/ClockInReminder.app/Contents/MacOS/ClockInReminder 10:10 19:10
```

不提供时间参数时使用 `10:00 19:10`；只提供第一个参数时，下班仍为 `19:10`。支持 `9:08`、`09:08` 和中文冒号 `10：10`。采用 24 小时制，上班时间须早于同一天的下班时间；非法时间会报错退出，不改动确认记录。

要让登录自启和重启恢复也使用这些时间，在安装或更新时传入相同参数：

```bash
bash install.sh 10:10 19:10
```

使用已编译程序安装：

```bash
bash install.sh 10:10 19:10 --prebuilt
```

安装脚本会同步更新程序启动参数和 launchd 日历条目。菜单栏、提醒窗口、今日状态和菜单栏演示均显示配置的时间。再次安装时若不传时间，会恢复默认的 `10:00 19:10`。

修改时间前退出已有实例；新启动参数不会改变已经运行的进程。已确认的“日期/上班或下班”继续保留，不因修改时刻重复提醒；未确认项按新时刻计算。手动双击 `.app` 会使用默认时间，常驻使用以安装配置为准。

## 演示与确认记录

菜单栏选择“演示提醒（不写记录）”，或在解压目录执行：

```bash
dist/ClockInReminder.app/Contents/MacOS/ClockInReminder --preview
```

演示中的“已打卡”和“退出演示”均关闭演示，不影响正式记录。正式窗口没有关闭、最小化按钮；Esc、⌘W、⌘M、⌘H 不会完成或关闭提醒，⌘Q 会进入紧急退出确认。

每个工作日保存两类确认，键为“本地日期/上班或下班”。记录文件位于：

```text
~/Library/Application Support/ClockInReminder/confirmations.json
```

菜单栏可打开这个目录。保存成功后窗口才消失；保存失败会提示错误并保留待办。重新登录、程序重启、电脑重启后，已确认项不重复出现。

## 紧急退出

窗口或菜单栏选择“紧急退出（暂停 15 分钟）”，再选择“暂停并退出”。程序退出，暂停保存在本机，**不会写入打卡确认**。安装的后台服务会在暂停到期后约 1 分钟内重新启动；电脑睡眠、未登录或系统延迟时会推迟。

窗口获得键盘焦点时也可按 `⌃⌥⌘Q`。这是应用内快捷键，不是全局快捷键。窗口失去响应时可用 macOS“强制退出”或“活动监视器”；后台服务可能再次拉起程序，永久停止使用卸载命令。

提前恢复提醒：

```bash
"$HOME/Applications/ClockInReminder.app/Contents/MacOS/ClockInReminder" --resume
launchctl kickstart "gui/$(id -u)/local.clockin.reminder"
```

## 卸载

在解压目录执行：

```bash
bash uninstall.sh
```

解压目录已删除时执行：

```bash
bash "$HOME/Applications/ClockInReminder.app/Contents/Resources/Support/uninstall.sh"
```

卸载会停止后台服务、结束安装目录内的进程，删除程序和 LaunchAgent。默认保留确认记录，重装继续使用。

需要同时删除确认记录和日志时执行以下命令；删除后重装会从当天重新开始：

```bash
bash uninstall.sh --purge
```

## 行为与排障

- [运行规则与实现](docs/BEHAVIOR.md)：补提醒、跨天、时区、多显示器和权限边界。
- [故障排查](docs/TROUBLESHOOTING.md)：未启动、无声音、记录损坏和手动停止。
- [验证记录](docs/VERIFICATION.md)：本机编译、测试结果和未验证的场景。

源码位于 `Sources/`。修改后运行 `bash test.sh`、`bash build.sh`，再运行 `bash install.sh --prebuilt` 更新；自定义时间时附上两个时间参数。程序不联网，不需要辅助功能、屏幕录制、通知权限或管理员密码。

## 许可证

本项目使用 **GNU General Public License v3.0（GPL-3.0-only）**，完整文本见 [LICENSE](LICENSE)。源码、脚本、文档及项目自带的生成音效适用同一许可证。macOS 的系统音效不包含在本仓库中。
