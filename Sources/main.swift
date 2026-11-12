// SPDX-License-Identifier: GPL-3.0-only
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
var preview = false
var settingsPreview = Bundle.main.object(forInfoDictionaryKey: "AttendanceReminderPreview") as? Bool == true
var openSettingsAtLaunch = false
var silent = false
var autoExit: TimeInterval? = settingsPreview ? 120 : nil
var directory = StateStore.defaultDirectory
var command: String?
var timeArguments: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--preview": preview = true
    case "--settings-preview": settingsPreview = true
    case "--settings": openSettingsAtLaunch = true
    case "--silent": silent = true
    case "--initialize", "--status", "--resume", "--validate-times", "--configure", "--disable-login":
        if command != nil { fputs("只接受一个操作参数。\n", stderr); exit(2) }
        command = argument
    case "--state-dir":
        index += 1
        guard index < arguments.count, arguments[index].hasPrefix("/") else {
            fputs("--state-dir 需要绝对路径。\n", stderr); exit(2)
        }
        directory = URL(fileURLWithPath: arguments[index], isDirectory: true)
    case "--auto-exit":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), value >= 1, value <= 300 else {
            fputs("--auto-exit 需要 1 至 300 秒。\n", stderr); exit(2)
        }
        autoExit = value
    case "--help":
        print("""
        ClockInReminder [上班时间] [下班时间] [选项]
          首次默认 10:00 19:10；无参数时沿用已保存设置。例：ClockInReminder 10:10 19:10
          仅提供第一个时间时，下班时间仍为 19:10。使用 24 小时制。
          --preview [--silent] [--auto-exit 1...300]  演示，读取音效设置，不写打卡确认
          --settings                                打开设置窗口
          --settings-preview [--auto-exit 1...300]    预览设置，不修改记录或系统登录项
          --initialize                              初始化当日起的记录
          --status                                  输出记录与待确认数量
          --resume                                  程序退出后清除暂停；随后手动打开应用
          --state-dir /absolute/path                使用独立的记录目录
          --validate-times                          校验并输出规范化后的两个时间，不读写记录
          --configure                               保存时间设置（开发者命令）
          --disable-login                           注销当前应用的登录启动（卸载用）
        """)
        exit(0)
    default:
        if argument.hasPrefix("-") { fputs("未知参数：\(argument)\n", stderr); exit(2) }
        timeArguments.append(argument)
    }
    index += 1
}
if (silent || autoExit != nil) && !preview && !settingsPreview {
    fputs("--silent 和 --auto-exit 仅可用于预览。\n", stderr); exit(2)
}
if (preview || settingsPreview) && command != nil { fputs("演示不能同时执行记录操作。\n", stderr); exit(2) }
if preview && settingsPreview { fputs("一次只预览一种窗口。\n", stderr); exit(2) }

let times: ReminderTimes
do { times = try ReminderTimes(arguments: timeArguments) }
catch { fputs("\(error.localizedDescription)\n", stderr); exit(2) }
if command == "--validate-times" {
    print(times.arguments.joined(separator: " "))
    exit(0)
}
if command == "--disable-login" {
    do { try LoginStartup(preview: false).setEnabled(false); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

if let command = command {
    do {
        let store = try StateStore(directory: directory)
        if command == "--status" {
            guard FileManager.default.fileExists(atPath: store.stateURL.path) else {
                print("尚未初始化记录。"); exit(0)
            }
            // 状态查询只读取，避免占用常驻进程的写锁。
            let state = try store.loadOrCreate(now: Date(), calendar: Schedule.calendar())
            let effectiveTimes = timeArguments.isEmpty ? (try store.loadPreferences()?.times ?? times) : times
            let now = Date()
            let calendar = Schedule.calendar()
            let pending = Schedule.pending(state: state, now: now, calendar: calendar, times: effectiveTimes)
            let day = Schedule.dayKey(now, calendar: calendar)
            print("本次查询时刻：\(effectiveTimes.morning.text) / \(effectiveTimes.evening.text)")
            for slot in PunchSlot.allCases {
                print("\(slot.title)：今日已确认 \(state.confirmationCount(on: day, slot: slot)) 次，待确认 \(pending.filter { $0.slot == slot }.count) 项")
            }
            print("开始日期：\(state.firstDay)\n记录：\(store.stateURL.path)")
            if let until = try store.activePause(now: Date()) { print("紧急暂停至：\(until.ISO8601Format())") }
        } else {
            let lock = try InstanceLock(directory: directory)
            try withExtendedLifetime(lock) {
                if command == "--configure" {
                    var value = try store.loadPreferences() ?? Preferences()
                    value.morning = times.morning.text
                    value.evening = times.evening.text
                    try store.savePreferences(value)
                    print("已保存时间：\(times.morning.text) / \(times.evening.text)")
                } else if command == "--resume" {
                    try store.clearPause()
                    print("已清除紧急暂停。")
                } else {
                    let state = try store.loadOrCreate(now: Date(), calendar: Schedule.calendar())
                    print("记录就绪，开始日期：\(state.firstDay)")
                }
            }
        }
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = ReminderApplication(directory: directory, preview: preview, silent: silent, autoExit: autoExit,
    times: timeArguments.isEmpty ? nil : times, settingsPreview: settingsPreview, openSettingsAtLaunch: openSettingsAtLaunch)
application.delegate = delegate
application.run()
