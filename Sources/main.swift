// SPDX-License-Identifier: GPL-3.0-only
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
var preview = false
var silent = false
var autoExit: TimeInterval?
var directory = StateStore.defaultDirectory
var command: String?
var timeArguments: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--preview": preview = true
    case "--silent": silent = true
    case "--initialize", "--status", "--resume", "--validate-times":
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
          默认 10:00 19:10；例：ClockInReminder 10:10 19:10
          仅提供第一个时间时，下班时间仍为 19:10。使用 24 小时制。
          --preview [--silent] [--auto-exit 1...300]  演示，不读取或写入正式记录
          --initialize                              初始化当日起的记录
          --status                                  输出记录与待确认数量
          --resume                                  清除紧急暂停；随后由 launchd 启动
          --state-dir /absolute/path                使用独立的记录目录
          --validate-times                          校验并输出规范化后的两个时间，不读写记录
        """)
        exit(0)
    default:
        if argument.hasPrefix("-") { fputs("未知参数：\(argument)\n", stderr); exit(2) }
        timeArguments.append(argument)
    }
    index += 1
}
if (silent || autoExit != nil) && !preview {
    fputs("--silent 和 --auto-exit 仅可用于 --preview。\n", stderr); exit(2)
}
if preview && command != nil { fputs("演示不能同时执行记录操作。\n", stderr); exit(2) }

let times: ReminderTimes
do { times = try ReminderTimes(arguments: timeArguments) }
catch { fputs("\(error.localizedDescription)\n", stderr); exit(2) }
if command == "--validate-times" {
    print(times.arguments.joined(separator: " "))
    exit(0)
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
            let count = Schedule.pending(state: state, now: Date(), calendar: Schedule.calendar(), times: times).count
            print("本次查询时刻：\(times.morning.text) / \(times.evening.text)")
            print("开始日期：\(state.firstDay)\n已确认：\(state.confirmations.count)\n待确认：\(count)\n记录：\(store.stateURL.path)")
            if let until = try store.activePause(now: Date()) { print("紧急暂停至：\(until.ISO8601Format())") }
        } else {
            let lock = try InstanceLock(directory: directory)
            try withExtendedLifetime(lock) {
                if command == "--resume" {
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
let delegate = ReminderApplication(directory: directory, preview: preview, silent: silent, autoExit: autoExit, times: times)
application.delegate = delegate
application.run()
