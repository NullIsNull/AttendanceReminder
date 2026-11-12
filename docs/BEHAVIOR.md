# 运行规则与实现

## 调度与确认

| 场景 | 行为 |
| --- | --- |
| 周一至周五 | 按启动参数生成上班、下班提醒，默认本地 10:00、19:10 |
| 周六、周日 | 不生成新提醒；仍可补出之前工作日的遗漏项 |
| 首次启用 | 从当日本地日期开始，补出今天已到点的项目 |
| 睡眠、关机、退出登录 | 不唤醒电脑；恢复运行后按记录补出遗漏项 |
| 跨多天未确认 | 按日期、上班、下班顺序逐项补提醒，不自动过期 |
| 已确认 | 相同本地日期和时段不重复提醒 |
| 重复点击 | 同一键只保存第一次确认；下一项需要再次点击 |
| 紧急退出 | 保存 15 分钟暂停并退出，不增加确认记录 |
| 保存失败 | 保留当前提醒；提示错误 |
| 记录损坏或版本不支持 | 报错并保留原文件，不重建空历史 |

不处理节假日、调休或请假。周一至周五固定视为工作日；长期离开后仍要逐项确认遗漏提醒。历史补提醒只表示本机提醒已处理，不能补交考勤。若需重置全部历史，卸载时用 `--purge`，重装从当天开始。

使用公历和 Mac 当前时区，不固定为新加坡或哥伦比亚。时区变更后按新的本地日期和时间计算；相同日期的已确认时段不再提醒。跨国际日期变更线、手动修改系统日期可能生成新的日期待办，程序不会判断实际出勤地或修正人为时钟错误。

第一个、第二个时间参数分别控制上班和下班；省略值使用默认时间。`ReminderTimes` 校验 24 小时制和同日先后顺序。确认键保持“日期/时段”，修改时刻不会重置已确认项，历史未确认项按新时刻补提醒。

## 常驻与补提醒

`Sources/ReminderApplication.swift` 每 5 秒检查待办，并监听系统唤醒、屏幕唤醒、会话恢复、时区和系统时钟变化。正常运行时，到点后在下次检查显示窗口，通常不超过约 5 秒；系统繁忙、睡眠或会话未恢复时会推迟。

`write-agent.sh` 生成当前用户的 LaunchAgent：

- `RunAtLoad=true`：登录加载时启动。
- `KeepAlive.SuccessfulExit=false`：非正常退出后由 launchd 重启。
- `StartInterval=60`：进程退出后每分钟尝试启动，用于紧急暂停到期恢复。
- `StartCalendarInterval`：按安装参数生成周一至周五的十个日历条目，默认 10:00、19:10。
- `ThrottleInterval=15`：限制短时间内反复启动。
- `LimitLoadToSessionType=Aqua`：在图形登录会话中运行。

`ProgramArguments` 同时写入规范化后的两个时间，登录、异常退出恢复和紧急暂停到期后继续使用安装时设置的时间。`--validate-times` 只校验并输出两个时间，不读写确认记录。

Apple 当前本机 `man launchd.plist` 说明：`StartInterval` 在睡眠期间会漏过；`StartCalendarInterval` 的遗漏触发会在唤醒时合并。程序依据持久化记录重新计算待办，不依赖触发次数恢复遗漏。LaunchAgent 的用户会话行为见 [Apple launchd 文档](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)；唤醒通知使用 [NSWorkspace.didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)。

## 窗口与退出

每个显示器有一个同步显示当前待办的窗口；任一窗口确认后同步更新。窗口采用 `NSPanel`、`screenSaver` 层级、`canJoinAllSpaces` 和 [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)。每 5 秒将窗口放回前面；只在首次展示、切换待办或重建窗口时请求激活，避免持续抢走考勤页面的键盘焦点。

窗口不提供普通关闭和最小化按钮。确认按钮没有回车快捷键，避免提醒突然出现时把正在输入的回车当作打卡确认。用户仍可用键盘辅助导航选择按钮。

强提醒依赖普通 macOS 应用窗口机制，无法阻止“强制退出”、系统注销、关机或卸载，也不能覆盖锁屏和系统安全界面。Spaces、全屏应用和多显示器的实际显示受系统设置影响，验证范围见验证记录。程序不屏蔽系统输入、不改变系统音量、不禁用安全退出。

每 30 秒尝试播放系统 `Ping` 音效，失败则使用包内 `reminder.wav`。两条播放路径都使用 `NSSound.volume` 控制提示音自身音量，按 20%、40%、60%、80%、100% 递增，此后保持 100%。每条新待办、重新启动或紧急暂停后恢复，均从 20% 开始；同一待办的窗口重建不重置音量。

程序不调用无法单独控制音量的系统 `beep` 作为后备，避免低音量阶段突然以系统音量播放。两条播放路径均失败时写错误日志，窗口继续提醒。[NSSound.volume](https://developer.apple.com/documentation/appkit/nssound/volume) 不改变系统音量；静音、输出设备和系统音效设置仍会影响听感。`Resources/reminder.wav` 为程序生成的双频提示音。

## 文件与持久化

| 路径 | 内容 |
| --- | --- |
| `~/Applications/ClockInReminder.app` | 程序及内置卸载脚本 |
| `~/Library/LaunchAgents/local.clockin.reminder.plist` | 登录启动与恢复配置 |
| `~/Library/Application Support/ClockInReminder/confirmations.json` | 启用日期、逐日确认记录 |
| `~/Library/Application Support/ClockInReminder/emergency-pause.json` | 最近一次紧急暂停期限 |
| `~/Library/Application Support/ClockInReminder/instance.lock` | 单实例写锁；空文件保留属于正常情况 |
| `~/Library/Logs/ClockInReminder/agent.log` | 标准输出 |
| `~/Library/Logs/ClockInReminder/agent-error.log` | 错误及暂停期间的启动说明 |

`Sources/ReminderCore.swift` 用独占文件锁防止双实例同时写入。确认文件通过原子替换写入，并同步文件内容，写入成功后才推进内存状态。记录包含计划时间、确认时间和时区。程序不收集公司账号、密码或考勤接口信息。

## 开发与隔离验收

```bash
bash test.sh
bash build.sh
bash Tests/cli.sh
bash Tests/integration.sh
```

`Tests/integration.sh` 在临时目录安装和卸载，不注册后台服务。`install.sh --stage /absolute/test-directory` 提供相同的隔离安装方式，`uninstall.sh --stage /absolute/test-directory` 删除该副本。不要把隔离目录设置为现有的用户目录。

命令行支持 `--state-dir /absolute/path`，供独立状态验证；演示使用 `--preview`，不读取或写入正式状态。`--preview --silent --auto-exit 30` 可用于自动退出的静音演示。正式模式不接受静音或自动退出参数。
