// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

enum PunchSlot: String, Codable, CaseIterable {
    case morning, evening

    var title: String { self == .morning ? "上班打卡" : "下班打卡" }
}

struct ClockTime: Equatable {
    let hour: Int
    let minute: Int
    var text: String { String(format: "%02d:%02d", hour, minute) }
    var minutesSinceMidnight: Int { hour * 60 + minute }

    init(_ input: String) throws {
        let normalized = input.replacingOccurrences(of: "：", with: ":")
        guard normalized.range(of: "^[0-9]{1,2}:[0-9]{2}$", options: .regularExpression) != nil else {
            throw ReminderError.system("时间格式不正确：\(input)。使用 24 小时制，例如 10:10、19:10。")
        }
        let parts = normalized.split(separator: ":")
        guard let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw ReminderError.system("时间超出范围：\(input)。小时为 00–23，分钟为 00–59。")
        }
        self.hour = hour
        self.minute = minute
    }
}

struct ReminderTimes: Equatable {
    let morning: ClockTime
    let evening: ClockTime
    var revisions: [String: String] = [:]
    static let defaults = try! ReminderTimes(arguments: [])

    init(arguments: [String]) throws {
        guard arguments.count <= 2 else { throw ReminderError.system("最多提供两个时间参数：上班时间 下班时间。") }
        morning = try ClockTime(arguments.first ?? "10:00")
        evening = try ClockTime(arguments.count == 2 ? arguments[1] : "19:10")
        guard morning.minutesSinceMidnight < evening.minutesSinceMidnight else {
            throw ReminderError.system("上班时间须早于同一天的下班时间。")
        }
    }

    func time(for slot: PunchSlot) -> ClockTime { slot == .morning ? morning : evening }
    func revision(on day: String, for slot: PunchSlot) -> String? {
        revisions["\(day)/\(slot.rawValue)"]
    }
    var arguments: [String] { [morning.text, evening.text] }
}

struct SoundRamp {
    private var step = 0

    mutating func nextVolume() -> Float {
        let volume = Float(step + 1) / 5
        step = min(step + 1, 4)
        return volume
    }

    mutating func reset() { step = 0 }
}

enum SoundChoice: String, Codable, CaseIterable {
    case ping = "Ping", glass = "Glass", pop = "Pop", purr = "Purr", submarine = "Submarine"
    case chime, silent

    var title: String {
        switch self {
        case .ping: return "清脆 · Ping"
        case .glass: return "玻璃 · Glass"
        case .pop: return "轻响 · Pop"
        case .purr: return "轻颤 · Purr"
        case .submarine: return "潜艇 · Submarine"
        case .chime: return "内置铃声"
        case .silent: return "无声音"
        }
    }
}

struct Preferences: Codable, Equatable {
    var version = 1
    var morning = "10:00"
    var evening = "19:10"
    var sound: SoundChoice = .ping
    var increasingVolume = true
    var maximumVolume: Double = 1
    var scheduleRevisions: [String: String]?

    func validated() throws -> Preferences {
        guard version == 1 else { throw ReminderError.system("设置版本不支持，请保留原文件并联系维护者。") }
        let times = try ReminderTimes(arguments: [morning, evening])
        guard maximumVolume.isFinite, (0.1...1).contains(maximumVolume) else {
            throw ReminderError.system("最大音量须在 10% 到 100% 之间。")
        }
        for (key, revision) in scheduleRevisions ?? [:] {
            let parts = key.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  Schedule.dayDate(String(parts[0]), calendar: Schedule.calendar()) != nil,
                  PunchSlot(rawValue: String(parts[1])) != nil, UUID(uuidString: revision) != nil else {
                throw ReminderError.system("重新提醒的设置记录无效，请保留原文件。")
            }
        }
        var result = self
        result.morning = times.morning.text
        result.evening = times.evening.text
        return result
    }

    var times: ReminderTimes {
        var result = try! ReminderTimes(arguments: [morning, evening])
        result.revisions = scheduleRevisions ?? [:]
        return result
    }
}

enum StartupStatus {
    case disabled, enabled, needsApproval, unavailable

    var isRequested: Bool { self == .enabled || self == .needsApproval }
    var description: String {
        switch self {
        case .disabled: return "已关闭，登录 Mac 后不会自动打开。"
        case .enabled: return "已开启，登录 Mac 后自动在菜单栏运行。"
        case .needsApproval: return "等待系统允许，请打开系统登录项完成设置。"
        case .unavailable: return "系统未找到此应用，请移到“应用程序”后重试。"
        }
    }
}

enum LegacyConfiguration {
    static func times(from data: Data) throws -> ReminderTimes {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == "local.clockin.reminder",
              let arguments = plist["ProgramArguments"] as? [String], !arguments.isEmpty else {
            throw ReminderError.system("旧版启动配置格式不正确，未修改该文件。")
        }
        return try ReminderTimes(arguments: Array(arguments.dropFirst().prefix { !$0.hasPrefix("-") }))
    }
}

struct ReminderEvent: Equatable {
    let day: String
    let slot: PunchSlot
    let scheduledAt: Date
    let timeZone: String
    var revision: String?
    var id: String { "\(day)/\(slot.rawValue)" }
}

struct Confirmation: Codable {
    let day: String
    let slot: PunchSlot
    let scheduledAt: Date
    let confirmedAt: Date
    let timeZone: String
    var revision: String?
}

struct ReminderState: Codable {
    var version = 1
    let firstDay: String
    let createdAt: Date
    var confirmations: [String: Confirmation] = [:]
    var previousConfirmations: [Confirmation]?

    func confirmation(on day: String, slot: PunchSlot, times: ReminderTimes) -> Confirmation? {
        guard let value = confirmations["\(day)/\(slot.rawValue)"],
              value.revision == times.revision(on: day, for: slot) else { return nil }
        return value
    }
}

struct EmergencyPause: Codable {
    let requestedAt: Date
    let until: Date
}

enum ReminderError: LocalizedError {
    case invalidState(String)
    case alreadyRunning
    case system(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let detail): return "记录文件无法读取：\(detail)。原文件已保留，请从备份恢复后重试。"
        case .alreadyRunning: return "程序已在运行。"
        case .system(let detail): return detail
        }
    }
}

enum Schedule {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US_POSIX")
        result.timeZone = timeZone
        return result
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func dayDate(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              dayKey(date, calendar: calendar) == key else { return nil }
        return date
    }

    static func events(on day: Date, calendar: Calendar, times: ReminderTimes = .defaults) -> [ReminderEvent] {
        guard (2...6).contains(calendar.component(.weekday, from: day)) else { return [] }
        return PunchSlot.allCases.compactMap { slot in
            let time = times.time(for: slot)
            guard let date = calendar.date(bySettingHour: time.hour, minute: time.minute,
                                           second: 0, of: day) else { return nil }
            let key = dayKey(day, calendar: calendar)
            return ReminderEvent(day: key, slot: slot, scheduledAt: date, timeZone: calendar.timeZone.identifier,
                                 revision: times.revision(on: key, for: slot))
        }
    }

    static func pending(state: ReminderState, now: Date, calendar: Calendar, times: ReminderTimes = .defaults) -> [ReminderEvent] {
        guard var day = dayDate(state.firstDay, calendar: calendar) else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [ReminderEvent] = []
        while day <= today {
            result += events(on: day, calendar: calendar, times: times).filter {
                $0.scheduledAt <= now && state.confirmation(on: $0.day, slot: $0.slot, times: times) == nil
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    static func nextEvent(state: ReminderState, now: Date, calendar: Calendar,
                          times: ReminderTimes = .defaults) -> ReminderEvent? {
        if let overdue = pending(state: state, now: now, calendar: calendar, times: times).first { return overdue }
        guard let firstDay = dayDate(state.firstDay, calendar: calendar) else { return nil }
        var day = max(firstDay, calendar.startOfDay(for: now))
        while true {
            if let event = events(on: day, calendar: calendar, times: times).first(where: {
                $0.scheduledAt >= now && state.confirmation(on: $0.day, slot: $0.slot, times: times) == nil
            }) { return event }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { return nil }
            day = next
        }
    }
}

final class StateStore {
    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("confirmations.json") }
    var pauseURL: URL { directory.appendingPathComponent("emergency-pause.json") }
    var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClockInReminder", isDirectory: true)
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func loadOrCreate(now: Date, calendar: Calendar) throws -> ReminderState {
        if !FileManager.default.fileExists(atPath: stateURL.path) {
            let initial = ReminderState(firstDay: Schedule.dayKey(now, calendar: calendar), createdAt: now)
            try write(initial, at: stateURL)
            return initial
        }
        do {
            let state = try decode(ReminderState.self, at: stateURL)
            guard state.version == 1, Schedule.dayDate(state.firstDay, calendar: calendar) != nil else {
                throw ReminderError.invalidState("版本或起始日期不正确")
            }
            for (key, value) in state.confirmations {
                guard key == "\(value.day)/\(value.slot.rawValue)",
                      Schedule.dayDate(value.day, calendar: calendar) != nil else {
                    throw ReminderError.invalidState("确认记录键不正确")
                }
            }
            for value in Array(state.confirmations.values) + (state.previousConfirmations ?? []) {
                guard Schedule.dayDate(value.day, calendar: calendar) != nil,
                      value.revision == nil || UUID(uuidString: value.revision!) != nil else {
                    throw ReminderError.invalidState("确认记录的日期或重新提醒标记不正确")
                }
            }
            return state
        } catch {
            throw ReminderError.invalidState(error.localizedDescription)
        }
    }

    func confirm(_ event: ReminderEvent, at now: Date, state: inout ReminderState) throws {
        if let existing = state.confirmations[event.id], existing.revision == event.revision { return }
        var candidate = state
        if let existing = candidate.confirmations[event.id] {
            candidate.previousConfirmations = (candidate.previousConfirmations ?? []) + [existing]
        }
        candidate.confirmations[event.id] = Confirmation(day: event.day, slot: event.slot,
            scheduledAt: event.scheduledAt, confirmedAt: now, timeZone: event.timeZone, revision: event.revision)
        // 写盘成功后才推进内存状态，否则窗口会把保存失败误当作已确认。
        try write(candidate, at: stateURL)
        state = candidate
    }

    func pause(until: Date, now: Date) throws {
        try write(EmergencyPause(requestedAt: now, until: until), at: pauseURL)
    }

    func activePause(now: Date) throws -> Date? {
        guard FileManager.default.fileExists(atPath: pauseURL.path) else { return nil }
        let value = try decode(EmergencyPause.self, at: pauseURL)
        return value.until > now ? value.until : nil
    }

    func clearPause() throws {
        if FileManager.default.fileExists(atPath: pauseURL.path) {
            try FileManager.default.removeItem(at: pauseURL)
        }
    }

    func loadPreferences() throws -> Preferences? {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return nil }
        return try decode(Preferences.self, at: preferencesURL).validated()
    }

    @discardableResult
    func savePreferences(_ preferences: Preferences, now: Date = Date(), calendar: Calendar = Schedule.calendar()) throws -> Preferences {
        var candidate = try preferences.validated()
        if let previous = try loadPreferences() {
            var revisions = previous.scheduleRevisions ?? [:]
            let day = Schedule.dayKey(now, calendar: calendar)
            if candidate.morning != previous.morning {
                revisions["\(day)/morning"] = UUID().uuidString
            }
            if candidate.evening != previous.evening {
                revisions["\(day)/evening"] = UUID().uuidString
            }
            candidate.scheduleRevisions = revisions.isEmpty ? nil : revisions
        }
        // 时间与本次重新提醒标记一次写入，重启后不会丢失或重复重置。
        try write(candidate, at: preferencesURL)
        return candidate
    }
}

final class InstanceLock {
    private let descriptor: Int32

    init(directory: URL) throws {
        let path = directory.appendingPathComponent("instance.lock").path
        descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ReminderError.system("无法打开运行锁：\(String(cString: strerror(errno)))") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw ReminderError.alreadyRunning }
            throw ReminderError.system("无法获取运行锁：\(String(cString: strerror(code)))")
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
