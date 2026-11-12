# 验证记录

版本：2.0.0。日期：2026-11-12，Asia/Singapore。环境：Apple Silicon、macOS 27.2（26B123）、Apple Swift 6.4.2、Command Line Tools。

## 已验证

| 项目 | 结果 |
| --- | --- |
| 原生编译 | arm64、x86_64 均成功，合并为 Universal 2，最低目标 macOS 13 |
| Intel 指令执行 | Apple Silicon 上通过 Rosetta 运行 x86_64 命令，输出自定义时间 10:10 / 19:10 |
| 本地签名 | codesign 严格验证通过，隔离安装副本也通过 |
| 核心逻辑 | 49 项测试通过，0 项失败 |
| 命令行 | 默认、单参数、双参数、中文冒号、非法参数拒绝且不写状态通过 |
| 隔离安装 | 包含空格、中文、& 的路径安装成功；更新保留设置和确认记录 |
| 隔离卸载 | 默认保留数据，重装沿用；清除模式删除测试数据 |
| 原生设置窗口 | 已取得截图，时间、声音、渐强、音量、启动状态与保存按钮完整显示 |
| 界面操作 | 独立预览中将时间从 10:00 改为 10:01、音效改为 Glass、音量改为 60%、关闭渐强，并点击保存结束预览 |
| 应用图标 | 原生生成 ICNS，sips 可读取 1024 × 1024 图像 |
| DMG | HFS+ 文件系统、UDZO 压缩，hdiutil verify 校验通过 |
| Dock 配置 | Info.plist 的 LSUIElement 为 true，运行入口设置 accessory 激活策略 |

49 项测试覆盖时间边界、五个工作日和周末、睡眠跨两次提醒、跨天遗漏、启用当日补提醒、确认持久化和重启去重、双次确认、重复点击、时钟回拨、时区与夏令时、损坏记录、未知版本、写入失败、单实例锁、暂停持久化、渐强档位、设置持久化、设置和确认分离、音量与时间校验、全部音效往返、旧版参数解析和登录状态文案。

复验命令：

```bash
bash test.sh
bash build.sh
bash Tests/cli.sh
bash Tests/integration.sh
bash package-dmg.sh --no-build
```

## 验证边界

设置窗口使用独立预览副本，不修改正式打卡记录或系统登录项。已操作保存按钮；真实磁盘持久化由核心和隔离安装测试验证。没有在用户账号上实际注册、注销登录项，也没有执行旧版服务迁移、注销登录、重启或睡眠；相关系统交付行为仍需安装后的实机验收。旧版时间解析已测试，停止旧服务和备份 plist 的完整迁移未实测。

没有逐一实测多显示器、其他应用全屏空间、锁屏恢复、声音实际听感、Intel 实体机和 macOS 13–26。设置窗口截图不包含整个 Dock，Dock 隐藏的验证依据是应用配置与运行策略。

Intel 编译时工具链给出警告，但链接完成：

```text
ld: warning: ignoring file '.../libswiftCompatibilityPacks.a':
fat file missing arch 'x86_64', file has 'arm64,arm64e'
```

安装包采用本地临时签名，未做 Developer ID 签名或 Apple 公证，未宣称通过下载隔离后的 Gatekeeper 分发验收。

本次环境无法使用 DiskManagement 服务，`hdiutil create` 和 `imageinfo` 返回“设备未配置”。打包改为 `makehybrid -hfs` 直接生成文件，再转换为 UDZO；校验成功。未通过 Finder 实际挂载和拖入“应用程序”验收。
