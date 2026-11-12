# 验证记录

版本：1.1.0。验证日期：2026-11-12，Asia/Singapore。环境：Apple Silicon、macOS 27.2（26B123）、Apple Swift 6.4.2、Command Line Tools。

## 已通过

| 项目 | 结果 |
| --- | --- |
| Swift/AppKit 编译 | `arm64`、`x86_64` 均编译成功，合并为 Universal 2 程序 |
| 最低部署版本 | 编译目标为 macOS 13.0 |
| 本地签名 | `codesign --verify --strict` 通过；安装副本的签名也通过 |
| 核心逻辑 | 37 项测试通过，0 项失败 |
| 命令行参数 | 默认值、单参数、双参数、中文冒号、非法参数拒绝且不写状态均通过 |
| Intel 指令执行 | Apple Silicon 上通过 Rosetta 执行 `arch -x86_64 … 10:10 19:10 --validate-times` 成功 |
| Shell / plist | Shell 语法检查、Info.plist、安装产生的 LaunchAgent 检查通过 |
| 隔离安装 | 在包含空格、`&` 和中文的临时路径安装成功，路径写入 plist 后一致 |
| 更新 / 重装 | 测试确认记录逐字节保持一致 |
| 自定义时间安装 | 启动参数和十个工作日日历条目均使用自定义时间，非法时间不改动原配置 |
| 渐强音量 | 20% → 40% → 60% → 80% → 100%、封顶、新提醒重置均通过逻辑测试 |
| 后备音效 | 已打入程序，WAV 文件格式、声道和时长检查通过 |
| 默认卸载 | 删除程序和 LaunchAgent，保留确认记录 |
| 清除卸载 | `--purge` 删除隔离测试中的程序、确认记录和日志 |
| 原生窗口启动 | 1.0.0 曾实机启动成功；1.1.0 未重复进行界面交互验收 |

核心测试覆盖：默认与自定义时间的前后边界、单参数默认值、中文冒号、非法参数、五个工作日、周末、睡眠跨两次提醒、跨周末补提醒、启用当日补提醒、确认持久化、重启去重、双次确认、重复确认、修改时刻后去重、时钟回拨、时区变更、夏令时、非法日期、损坏文件、未知记录版本、写入失败、单实例锁、暂停跨重启、暂停到期、清除暂停、音量递增、音量封顶及重置。

复验命令：

```bash
bash test.sh
bash build.sh
bash Tests/cli.sh
bash Tests/integration.sh
```

## 未完成的实机验证

1.0.0 验收时临时 launchd 服务注册失败，输出为：

```text
Bootstrap failed: 5: Input/output error
Try re-running the command as root for richer errors.
```

当时仅运行 `/bin/sleep 30` 的最小 LaunchAgent 也返回相同错误，读取系统日志时返回 `log: Cannot run while sandboxed`。1.1.0 验证了生成的自定义时间配置，没有重新执行真实 launchd 注册、拉起、定期重启和停止验收，也没有替用户注册或修改正式登录自启。

包内 `Tests/launchd.sh` 可在普通终端复验。它创建唯一名称的临时服务，把恢复间隔缩短为 15 秒，检查命令启动两次后注销并清理；不安装正式服务。

```bash
bash Tests/launchd.sh
```

1.0.0 的界面检查工具在首次读取窗口后超时，未取得可复核截图，未完成按钮、紧急退出弹窗和多显示器的自动点击验收。1.1.0 未操作正式确认记录，也未启动新的常驻实例。

没有实际让用户的电脑睡眠、重启或注销。相关恢复逻辑通过可控时间和记录重读测试验证；系统事件交付仍需安装后的实机验收。多显示器、其他应用的全屏空间、锁屏恢复、渐强提示音的实际听感、Intel 实体机及 macOS 13–26 未逐一实测。

Intel 编译时工具链输出以下警告；链接仍成功，Rosetta 下命令行运行成功：

```text
ld: warning: ignoring file '.../libswiftCompatibilityPacks.a':
fat file missing arch 'x86_64', file has 'arm64,arm64e'
```

安装包使用本地临时签名，未做 Developer ID 签名或 Apple 公证，未宣称通过下载隔离后的 Gatekeeper 分发验收。
