# 故障排查

## 菜单栏没有“打卡”

1. 检查是否处于紧急暂停，暂停期内程序会退出：

   ```bash
   "$HOME/Applications/ClockInReminder.app/Contents/MacOS/ClockInReminder" --status
   ```

   自定义时间时，查询也传入相同参数，例如在 `--status` 前加 `10:10 19:10`；输出会显示本次查询使用的时间。菜单栏中的“今日状态”直接使用运行实例的时间。

2. 检查后台服务：

   ```bash
   launchctl print "gui/$(id -u)/local.clockin.reminder"
   ```

   `Could not find service` 表示尚未注册，可重新运行安装脚本。

3. 查看错误日志：

   ```bash
   tail -n 40 "$HOME/Library/Logs/ClockInReminder/agent-error.log"
   ```

4. 检查“系统设置 → 通用 → 登录项与扩展”中是否允许这个程序在后台运行。不同 macOS 版本的名称可能不同。若程序被安全机制阻止，使用 README 中的本机编译方式重装。

不要用 `sudo` 安装，也不要修改 `/Library/LaunchDaemons`。本程序只在安装用户的图形登录会话中运行。

## 窗口挡住考勤页面

拖动窗口顶部，把窗口移到屏幕一侧，再操作考勤页面。多显示器窗口确认的是同一项，不会多记一次。无法操作或窗口失去响应时，使用紧急退出或手动停止。

## 没有提示音

检查 Mac 是否静音、输出设备是否连接、系统音效音量是否为零。首次提示音为自身音量的 20%，每 30 秒增大一档，正常连续播放约 2 分钟达到 100%。程序不会强制打开声音，也不会提高系统音量。演示命令带 `--silent` 时不会播放声音。

若日志出现“提示音播放失败”，系统音效和包内后备音效均未能播放，窗口提醒仍然有效。

## 确认记录无法读取或保存

先停止后台服务，保留原文件再处理。不要在程序运行时手动修改记录。

```bash
launchctl bootout "gui/$(id -u)/local.clockin.reminder"
open "$HOME/Library/Application Support/ClockInReminder"
```

从已有备份恢复 `confirmations.json`，或修复该目录的用户写权限。恢复后执行：

```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.clockin.reminder.plist"
```

没有备份且决定丢弃旧记录时，先把原文件复制到其他目录留存，再删除记录文件。重新启动会从当天初始化，旧的已确认信息不会自动恢复。只删除损坏文件即可，不需要修改程序源码。

## 手动停止与恢复

卸载脚本不可用时，先停止后台服务：

```bash
launchctl bootout "gui/$(id -u)/local.clockin.reminder"
```

这会结束由该服务启动的进程。手动双击启动的副本可在“活动监视器”中选择 `ClockInReminder` 并退出。停止后如要防止下次登录启动，可运行内置卸载脚本，或把对应 LaunchAgent 文件移出 `~/Library/LaunchAgents`。

需要恢复且 plist 仍在原位置时：

```bash
launchctl enable "gui/$(id -u)/local.clockin.reminder"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.clockin.reminder.plist"
```

已经加载时不重复 `bootstrap`，改用 `launchctl kickstart "gui/$(id -u)/local.clockin.reminder"`。
