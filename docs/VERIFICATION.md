# 验证记录

版本：2.1.1。日期：2026-11-12，Asia/Singapore。环境：Apple Silicon、macOS 27.2（26B123）、Apple Swift 6.4.2、Command Line Tools。

## 编译与自动检查

| 项目 | 结果 |
| --- | --- |
| 原生编译 | arm64、x86_64 均成功，Universal 2，最低运行目标 macOS 13 |
| 本地签名 | codesign 严格验证通过，隔离安装副本也通过 |
| 核心逻辑 | 53 项测试通过，0 项失败 |
| 命令行 | 默认、单参数、双参数、中文冒号、非法参数拒绝且不写状态通过 |
| 隔离安装与卸载 | 更新保留设置和确认记录，默认卸载保留数据，重装沿用，清除模式删除测试数据 |
| Intel 指令执行 | Rosetta 下 x86_64 命令输出 10:10 / 19:10 |
| DMG | HFS+、UDZO；hdiutil verify 校验通过，打包内容仅应用和 Applications 链接 |

核心测试覆盖调度边界、工作日和周末、唤醒补提醒计算、跨天遗漏、确认持久化和去重、时区与夏令时、损坏文件、写入失败、锁、暂停、音量渐强及设置持久化。

## 2.1.1 提醒回归

- 复现今日上班已确认后在 12:20 改为 12:21：12:21 不重复，下一项为下班；次日上班按新时间生成。
- 独立 `due` 测试在设置窗口打开时到点，12:33:04、12:33:39、12:34:09 触发 Ping 播放调用，音量依次为 6%、12%、18%；此时提醒窗口数为 0。这是调度和播放调用验证，未测量扬声器实际输出。
- 关闭设置后，两台显示器恢复 2 个提醒窗口。
- 独立 `confirmed` 测试显示今日上班已确认、下一次为下班；经过保存的上班时间后，播放次数和提醒窗口数仍为 0。
- 设置页面已显示今日两次确认、已保存设置的下次提醒及到点提示。
- 已打开精简后的菜单，确认只保留设置、今日状态、暂停、恢复和紧急退出，三项辅助菜单已移除。

## 2.1.0 已有界面回归

以下为前一版本的实测记录。

使用 `Tests/interface-preview.sh` 构建独立测试应用。它运行实际设置和提醒代码，使用隔离状态目录，禁用系统登录项变更。测试应用记录窗口可见状态，避免界面检查工具重新激活应用时把重新打开误判为关闭失败。

| 场景 | 操作与观察 |
| --- | --- |
| 浅色设置 | 原生玻璃面板、时间、音效、开关、音量和保存按钮完整显示 |
| 音量拖动 | 实际鼠标拖动从 100% 到约 51%，标签实时变化 |
| 设置保存 | 修改时间、Glass 音效、渐强开关和音量，JSON 文件与重新打开的控件一致 |
| 保存后关闭 | 再保存音量 75%，文件为 0.75；窗口状态为 settingsVisible=false、reminderWindows=0 |
| 非法时间 | 上下班设为同一时刻，显示“未保存：上班时间须早于同一天的下班时间。”；仍可继续操作 |
| 实例占用 | 同一目录持有第二个文件锁，设置显示行内冲突提示；保存失败原因可见，原设置未被覆盖 |
| 冲突后关闭 | 点击“关闭”后 settingsVisible=false、reminderWindows=0，没有置顶错误面板 |
| 深色提醒 | 已取得玻璃提醒窗口截图，确认按钮使用系统蓝色和白色内容 |
| 提醒与设置切换 | 两个显示器的提醒在打开设置后变为 0，关闭设置后恢复为 2 |
| 退出 | 测试副本退出后释放锁，无测试进程残留 |

复验命令：

```bash
bash test.sh
bash build.sh
bash Tests/cli.sh
bash Tests/integration.sh
bash package-dmg.sh --no-build
bash Tests/interface-preview.sh /absolute/test-directory settings
bash Tests/interface-preview.sh /absolute/test-directory conflict
bash Tests/interface-preview.sh /absolute/test-directory reminder dark
bash Tests/interface-preview.sh /absolute/test-directory due
bash Tests/interface-preview.sh /absolute/test-directory confirmed
```

界面测试程序不随正式应用分发。`conflict` 模式故意保持文件锁占用，用于验证错误后的交互；最多运行 5 分钟。`due` 和 `confirmed` 在工作日 23:00 前运行，首次启动时把上班设为下一分钟，分别创建未确认与已确认样本。其状态目录内记录及同级 `status-*.json` 均为测试数据；状态文件包含窗口数量和声音调用记录。

## 验证边界

未通过 Finder 实际挂载新版 DMG 并拖入“应用程序”，未切换系统减少透明度和增加对比度设置，未逐一实测旧版 macOS、Intel 实体机和其他应用的全屏空间。兼容外观与 Dock 隐藏依据是代码分支、系统颜色和 LSUIElement / accessory 配置。

未注册、注销真实登录项，未进行旧版 LaunchAgent 完整迁移、实际睡眠、重启或注销登录。没有修改或清空用户的正式确认记录。跨进程通知回执分支尚未单独完成双进程交互验收；文件锁占用场景已通过上述界面回归。

当前环境不能使用 DiskManagement 服务，打包采用 `makehybrid -hfs` 生成文件后转为 UDZO，无需挂载临时磁盘。Intel 编译有工具链缺少 x86_64 的 `libswiftCompatibilityPacks.a` 警告，链接和 Rosetta 命令仍通过。

安装包使用本地临时签名，未做 Developer ID 签名或 Apple 公证，未验证下载隔离后的 Gatekeeper 分发流程。
