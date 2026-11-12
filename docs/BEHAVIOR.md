# 运行规则与实现

## 调度和持久化

`Sources/ReminderCore.swift` 按公历和 Mac 当前时区生成工作日待办。`Sources/ReminderApplication.swift` 每 5 秒检查，并监听唤醒、会话恢复、时区、时钟和显示器变化。正常运行时到点后在下一次检查提醒；系统繁忙、睡眠或未登录时延后。

| 场景 | 行为 |
| --- | --- |
| 周一至周五 | 按设置生成上班、下班两项，首次默认 10:00、19:10 |
| 周末 | 不产生新项，仍补出之前工作日的遗漏 |
| 首次启用 | 从当日本地日期开始，不追溯更早日期 |
| 睡眠、关机、退出登录 | 不唤醒电脑，恢复运行后重新计算遗漏 |
| 跨多天未确认 | 按日期和时段逐项补提醒，不自动过期 |
| 已确认或重复点击 | 同一次时间设置只确认一次；重启不重复 |
| 修改提醒时间 | 当天修改的时段重新提醒；旧确认保留，未确认历史按新时间计算 |
| 暂停 | 持久化 15 分钟期限，进程保持运行，到期恢复 |
| 紧急退出 | 真正退出，不写确认，不自动在一分钟后拉起 |
| 保存失败 | 保留待办和原记录，提示错误 |
| 文件损坏或未知版本 | 报错并保留原文件，不静默重建历史 |

不处理节假日、调休或请假。跨国际日期变更线或手动修改日期可能形成新的日期待办，程序不判断实际出勤地点。

独占文件锁保护状态写入；确认、设置和暂停采用原子替换并同步文件内容，成功后才更新内存状态。确认键为“本地日期/时段”。每次实际修改并保存时间，在 preferences.json 的 scheduleRevisions 中为当天对应时段生成新标记，与时间一次原子写入。调度要求确认标记与当前设置匹配；重启和相同时间保存沿用标记。不同日期的标记分别保留，避免后续修改丢失历史补提醒。再次确认时，旧条目移入 previousConfirmations，最新条目与历史一次原子保存。旧版没有标记的设置和记录可直接读取。

## 窗口与声音

每个显示器有一个同步的 `NSPanel`，使用 `screenSaver` 层级、`canJoinAllSpaces` 和 `fullScreenAuxiliary`。窗口可拖动，每 5 秒重新置前；只在首次显示、切换待办或重建时激活，避免持续抢夺考勤页面的键盘焦点。打开设置前收起所有提醒窗口；设置可见时调度和 30 秒声音周期继续运行，只禁止创建置顶窗口和抢焦点。时间卡片显示今日确认、已保存设置的下次提醒，以及暂停或到点状态。关闭设置后重新检查待办并显示确认窗口。实例冲突和读取错误只在设置内显示可关闭的状态提示，不创建置顶错误面板。

提醒不提供关闭和最小化按钮；确认按钮不绑定回车，避免出现时误接收正在输入的回车。保留暂停、紧急退出及系统强制退出。普通应用窗口不能覆盖锁屏和系统安全界面，也不能阻止注销或关机。

`Sources/ReminderAudio.swift` 使用 `NSSound`。系统音效不可用时改用包内 `reminder.wav`；两条路径均按设置限制音量。每 30 秒播放一次，渐强档位为 20%、40%、60%、80%、100%，乘以配置的最大音量。每条新提醒或暂停恢复后重置，显示器变化造成的同一待办窗口重建不重置。关闭渐强后固定为最大音量，静音选项不播放。

不调用无法单独控制音量的系统 beep；两条播放路径均失败则写标准错误，窗口继续显示。包内声音和图标由项目生成，系统声音不随应用分发。

`Sources/Appearance.swift` 通过 `NSGlassEffectView.contentView` 承载窗口内容。macOS 26 及以上使用原生玻璃，macOS 13–15 使用 `NSVisualEffectView`；减少透明度时使用实色，增加对比度时强化边框。监听辅助功能显示设置变化，并使用语义颜色跟随明暗外观。

设置中的校验、写盘和登录项错误使用行内提示，迁移确认使用附属 sheet，避免高层级模态窗口阻挡输入。滑块连续发送数值变化；保存前结束日期控件编辑，读取最后输入的时刻。

## 设置与登录启动

`Sources/SettingsWindow.swift` 提供原生设置窗口。保存时间和音效后立即用于当前调度。登录启动开关即时调用 `Sources/LoginStartup.swift` 中的 `SMAppService.mainApp.register()` / `unregister()`，读取系统状态显示已开启、未开启、等待允许或不可用，不用自有布尔值伪装注册成功。

macOS 原生登录项由系统服务管理。新版不再写自定义 LaunchAgent，也不配置异常退出自动重启；进程退出后需再次打开或等待已启用的下次登录。应用需从 `/Applications` 或 `~/Applications` 运行后才能开启登录启动。

旧版迁移只处理标签为 `local.clockin.reminder` 的用户 LaunchAgent。先读取原时间，停止旧服务，再把旧 plist 改名为 `.disabled-UUID` 备份。新应用保留 bundle ID 和状态目录，沿用确认记录。迁移不替用户开启新登录项。

设置保存于 `~/Library/Application Support/ClockInReminder/preferences.json`；确认记录为同目录 `confirmations.json`；暂停为 `emergency-pause.json`；`instance.lock` 是单实例锁文件。旧版 `~/Library/Logs/ClockInReminder` 日志不再追加，新版错误输出到标准错误。

`LSUIElement=true` 和 `.accessory` 激活策略用于隐藏 Dock 图标；菜单栏使用单个模板图标，适应系统明暗模式。程序不联网，不请求通知、辅助功能或屏幕录制权限。

## 开发接口

在已退出常驻实例后，直接执行应用内程序可指定时间；两个参数分别为上班和下班：

```bash
dist/AttendanceReminder.app/Contents/MacOS/ClockInReminder 10:10 19:10
```

显式参数会保存到设置；仅传第一个时，第二个为 19:10。无参数时沿用已保存设置，全新安装才使用 10:00、19:10。支持单数字小时和中文冒号；上班必须早于同日下班，不支持跨夜班次。正在运行时修改设置请用界面，启动第二个实例时通过通知请求已有实例显示设置；收到持锁实例的回执后退出新实例。没有回执时保留可关闭的冲突提示，不凭磁盘上的版本号判断正在运行的版本。

`--status` 只读取确认状态，默认使用已保存时间。`--validate-times` 校验输入并输出规范化时间，不读写状态。`--configure` 在未运行时保存时间，供开发者安装脚本调用。

`--preview [--silent] [--auto-exit 1...300]` 演示提醒，可读取已保存音效，不写正式确认。`--settings-preview` 演示设置，不读写用户数据，也不修改系统登录项。`--state-dir /absolute/path` 指定隔离状态目录；它不隔离系统登录项，所以测试不得调用登录启动开关。

`Tests/integration.sh` 使用临时目录执行安装、更新和卸载，不注册系统登录项。`install.sh --stage /absolute/test-directory`、`uninstall.sh --stage /absolute/test-directory` 提供相同隔离入口。`--purge` 仅对需要销毁的测试数据使用。

## 平台依据

- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)：登录项注册及状态。
- [NSWorkspace.didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)：睡眠唤醒通知。
- [NSSound.volume](https://developer.apple.com/documentation/appkit/nssound/volume)：提示音自身音量。

[Apple Liquid Glass / AppKit 设计说明](https://developer.apple.com/videos/play/wwdc2025/310/)说明玻璃内容承载、系统控件形状与颜色层级。

`Tests/interface-preview.sh /absolute/test-directory settings|conflict|reminder [dark]` 构建隔离界面测试程序：使用独立记录、禁用系统登录项变更，5 分钟后自动退出。冲突模式持有第二个文件锁，用于复验保存失败仍可关闭设置。
