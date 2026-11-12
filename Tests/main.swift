// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct TestFailure: Error, CustomStringConvertible { let description: String }
var passed = 0
var failed = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}
func test(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("PASS \(name)") }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
let sg = Schedule.calendar(timeZone: TimeZone(identifier: "Asia/Singapore")!)
let ny = Schedule.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
func date(_ text: String, calendar: Calendar = sg) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: text)!
}
func initial(_ day: String = "2026-11-09") -> ReminderState {
    ReminderState(firstDay: day, createdAt: date("\(day) 00:00:00"))
}
let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("clockin-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: testRoot) }
func store() throws -> StateStore { try StateStore(directory: testRoot.appendingPathComponent(UUID().uuidString)) }

test("10:00 前不提醒") {
    try expect(Schedule.pending(state: initial(), now: date("2026-11-09 09:59:59"), calendar: sg).isEmpty, "提前提醒")
}
test("10:00 到点提醒") {
    let result = Schedule.pending(state: initial(), now: date("2026-11-09 10:00:00"), calendar: sg)
    try expect(result.count == 1 && result[0].slot == .morning, "上班时间边界错误")
}
test("19:10 前不生成下班提醒") {
    try expect(Schedule.pending(state: initial(), now: date("2026-11-09 19:09:59"), calendar: sg).count == 1, "下班提前提醒")
}
test("19:10 同日两项独立提醒") {
    let result = Schedule.pending(state: initial(), now: date("2026-11-09 19:10:00"), calendar: sg)
    try expect(result.map(\.slot) == [.morning, .evening], "时间或顺序错误")
}
test("五个工作日各两项") {
    let result = Schedule.pending(state: initial(), now: date("2026-11-13 23:00:00"), calendar: sg)
    try expect(result.count == 10, "工作日数量错误")
}
test("周末不产生新提醒") {
    try expect(Schedule.pending(state: initial("2026-11-14"), now: date("2026-11-15 23:59:59"), calendar: sg).isEmpty, "周末生成了提醒")
}
test("睡眠跨两次提醒后一次补齐") {
    let state = initial()
    let beforeSleep = Schedule.pending(state: state, now: date("2026-11-09 09:00:00"), calendar: sg)
    let afterWake = Schedule.pending(state: state, now: date("2026-11-09 20:00:00"), calendar: sg)
    try expect(beforeSleep.isEmpty && afterWake.count == 2, "唤醒补提醒错误")
}
test("跨周末唤醒保留历史并生成周一上班提醒") {
    let result = Schedule.pending(state: initial("2026-11-13"), now: date("2026-11-16 10:00:00"), calendar: sg)
    try expect(result.count == 3 && result.last?.day == "2026-11-16", "跨天补提醒错误")
}
test("周末可补出周五遗漏项") {
    try expect(Schedule.pending(state: initial("2026-11-13"), now: date("2026-11-14 12:00:00"), calendar: sg).count == 2, "历史提醒被周末过滤")
}
test("启用当日补提醒且不追溯此前日期") {
    let storage = try store()
    let state = try storage.loadOrCreate(now: date("2026-11-11 18:00:00"), calendar: sg)
    let result = Schedule.pending(state: state, now: date("2026-11-11 18:00:00"), calendar: sg)
    try expect(result.count == 1 && result[0].day == "2026-11-11", "起始日期错误")
}
test("确认写盘后重启不重复，并保留下班提醒") {
    let storage = try store()
    var state = try storage.loadOrCreate(now: date("2026-11-09 08:00:00"), calendar: sg)
    let event = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    try storage.confirm(event, at: date("2026-11-09 10:01:00"), state: &state)
    let reopened = try StateStore(directory: storage.directory).loadOrCreate(now: date("2026-11-09 20:00:00"), calendar: sg)
    let pending = Schedule.pending(state: reopened, now: date("2026-11-09 20:00:00"), calendar: sg)
    try expect(reopened.confirmations.count == 1 && pending.count == 1 && pending[0].slot == .evening, "重启去重失败")
}
test("两次确认后当日无待办") {
    let storage = try store()
    var state = try storage.loadOrCreate(now: date("2026-11-09 08:00:00"), calendar: sg)
    for event in Schedule.pending(state: state, now: date("2026-11-09 20:00:00"), calendar: sg) {
        try storage.confirm(event, at: date("2026-11-09 20:01:00"), state: &state)
    }
    let reopened = try storage.loadOrCreate(now: date("2026-11-09 21:00:00"), calendar: sg)
    try expect(reopened.confirmations.count == 2 && Schedule.pending(state: reopened, now: date("2026-11-09 21:00:00"), calendar: sg).isEmpty, "确认丢失")
}
test("重复确认不覆盖首次确认时间") {
    let storage = try store()
    var state = initial()
    let event = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    let first = date("2026-11-09 10:01:00")
    try storage.confirm(event, at: first, state: &state)
    try storage.confirm(event, at: date("2026-11-09 10:02:00"), state: &state)
    try expect(state.confirmations.count == 1 && state.confirmations[event.id]?.confirmedAt == first, "重复确认覆盖记录")
}
test("确认后回拨时钟不重复") {
    let storage = try store()
    var state = initial()
    let event = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    try storage.confirm(event, at: date("2026-11-09 10:01:00"), state: &state)
    try expect(Schedule.pending(state: state, now: date("2026-11-09 09:59:00"), calendar: sg).isEmpty, "回拨错误")
    try expect(Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg).isEmpty, "再次经过10点重复")
}
test("时区变更使用新的本地10点") {
    let state = initial()
    let now = date("2026-11-09 10:00:00", calendar: ny)
    let result = Schedule.pending(state: state, now: now, calendar: ny)
    try expect(result.count == 1 && result[0].scheduledAt == now && result[0].timeZone == "America/New_York", "新时区错误")
}
test("时区变更同一日期已确认项不重复") {
    let storage = try store()
    var state = initial()
    let event = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    try storage.confirm(event, at: date("2026-11-09 10:01:00"), state: &state)
    try expect(Schedule.pending(state: state, now: date("2026-11-09 10:00:00", calendar: ny), calendar: ny).isEmpty, "时区切换重复")
}
test("夏令时周末后仍为本地10点") {
    let result = Schedule.pending(state: initial("2026-03-06"), now: date("2026-03-09 10:00:00", calendar: ny), calendar: ny)
    try expect(result.count == 3 && ny.component(.hour, from: result.last!.scheduledAt) == 10, "DST 边界错误")
}
test("无效日期被拒绝") {
    try expect(Schedule.dayDate("2026-02-30", calendar: sg) == nil, "非法日期被接受")
    try expect(Schedule.dayDate("2026-2-01", calendar: sg) == nil, "非规范日期被接受")
}
test("损坏记录不被静默清空") {
    let storage = try store()
    let damaged = Data("{broken".utf8)
    try damaged.write(to: storage.stateURL)
    var rejected = false
    do { _ = try storage.loadOrCreate(now: Date(), calendar: sg) } catch { rejected = true }
    let preserved = try Data(contentsOf: storage.stateURL)
    try expect(rejected && preserved == damaged, "损坏记录被覆盖")
}
test("未知记录版本被拒绝") {
    let storage = try store()
    var state = initial()
    state.version = 999
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(state).write(to: storage.stateURL)
    var rejected = false
    do { _ = try storage.loadOrCreate(now: Date(), calendar: sg) } catch { rejected = true }
    try expect(rejected, "未知版本被接受")
}
test("保存失败不推进内存确认") {
    let storage = try store()
    var state = initial()
    try FileManager.default.createDirectory(at: storage.stateURL, withIntermediateDirectories: false)
    let event = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    var rejected = false
    do { try storage.confirm(event, at: Date(), state: &state) } catch { rejected = true }
    try expect(rejected && state.confirmations.isEmpty, "保存失败却推进确认")
}
test("独占锁阻止双实例写入，释放后可重新获取") {
    let storage = try store()
    var first: InstanceLock? = try InstanceLock(directory: storage.directory)
    var rejected = false
    withExtendedLifetime(first) {
        do { _ = try InstanceLock(directory: storage.directory) } catch ReminderError.alreadyRunning { rejected = true } catch {}
    }
    try expect(rejected, "双实例同时得到锁")
    first = nil
    let second = try InstanceLock(directory: storage.directory)
    withExtendedLifetime(second) {}
}
test("紧急暂停跨重启生效，到期恢复且不记作打卡") {
    let storage = try store()
    let now = date("2026-11-09 10:00:00")
    _ = try storage.loadOrCreate(now: now, calendar: sg)
    try storage.pause(until: now.addingTimeInterval(900), now: now)
    let reopened = try StateStore(directory: storage.directory)
    let active = try reopened.activePause(now: now.addingTimeInterval(899))
    let expired = try reopened.activePause(now: now.addingTimeInterval(900))
    let state = try reopened.loadOrCreate(now: now, calendar: sg)
    try expect(active != nil && expired == nil && state.confirmations.isEmpty, "暂停语义错误")
}
test("恢复操作清除暂停") {
    let storage = try store()
    try storage.pause(until: Date().addingTimeInterval(900), now: Date())
    try storage.clearPause()
    let active = try storage.activePause(now: Date())
    try expect(active == nil, "暂停未清除")
}

test("时间参数省略时保持10:00与19:10") {
    let times = try ReminderTimes(arguments: [])
    try expect(times.arguments == ["10:00", "19:10"], "默认时间错误")
}
test("只提供上班时间时下班仍为19:10") {
    let times = try ReminderTimes(arguments: ["10:10"])
    try expect(times.arguments == ["10:10", "19:10"], "单参数默认错误")
}
test("两个时间参数均生效") {
    let times = try ReminderTimes(arguments: ["09:08", "20:05"])
    try expect(times.morning.hour == 9 && times.morning.minute == 8 && times.evening.hour == 20 && times.evening.minute == 5, "参数解析错误")
}
test("单数字小时与中文冒号规范化") {
    let times = try ReminderTimes(arguments: ["9：08", "19：10"])
    try expect(times.arguments == ["09:08", "19:10"], "格式规范化错误")
}
test("时刻上下界00:00与23:59") {
    let times = try ReminderTimes(arguments: ["00:00", "23:59"])
    try expect(times.morning.minutesSinceMidnight == 0 && times.evening.minutesSinceMidnight == 1439, "时间边界错误")
}
test("非法时间格式和范围被拒绝") {
    for value in ["", "24:00", "10:60", "-1:00", "10:1", "10:00:00", "abc", " 10:00", "100:00"] {
        var rejected = false
        do { _ = try ClockTime(value) } catch { rejected = true }
        try expect(rejected, "接受了非法时间：\(value)")
    }
}
test("逆序、相同时间和多余参数被拒绝") {
    for arguments in [["20:00", "19:10"], ["10:00", "10:00"], ["10:00", "19:10", "20:00"]] {
        var rejected = false
        do { _ = try ReminderTimes(arguments: arguments) } catch { rejected = true }
        try expect(rejected, "接受了非法组合：\(arguments)")
    }
}
test("自定义上班时间不提前且到点提醒") {
    let times = try ReminderTimes(arguments: ["10:10", "19:10"])
    let before = Schedule.pending(state: initial(), now: date("2026-11-09 10:09:59"), calendar: sg, times: times)
    let at = Schedule.pending(state: initial(), now: date("2026-11-09 10:10:00"), calendar: sg, times: times)
    try expect(before.isEmpty && at.count == 1 && at[0].scheduledAt == date("2026-11-09 10:10:00"), "自定义上班调度错误")
}
test("自定义下班时间用于晚间提醒及跨天补提醒") {
    let times = try ReminderTimes(arguments: ["09:08", "20:05"])
    let before = Schedule.pending(state: initial(), now: date("2026-11-09 20:04:59"), calendar: sg, times: times)
    let at = Schedule.pending(state: initial(), now: date("2026-11-09 20:05:00"), calendar: sg, times: times)
    let nextDay = Schedule.pending(state: initial(), now: date("2026-11-10 08:00:00"), calendar: sg, times: times)
    try expect(before.count == 1 && at.count == 2 && nextDay == at, "自定义下班补提醒错误")
}
test("修改时刻不重复提醒同日已确认的时段") {
    let storage = try store()
    var state = initial()
    let oldEvent = Schedule.pending(state: state, now: date("2026-11-09 10:00:00"), calendar: sg)[0]
    try storage.confirm(oldEvent, at: date("2026-11-09 10:01:00"), state: &state)
    let times = try ReminderTimes(arguments: ["10:10", "19:10"])
    let reopened = try storage.loadOrCreate(now: date("2026-11-09 10:10:00"), calendar: sg)
    try expect(Schedule.pending(state: reopened, now: date("2026-11-09 10:10:00"), calendar: sg, times: times).isEmpty, "修改时间导致重复确认")
}
test("音量从20%逐次升至100%") {
    var ramp = SoundRamp()
    let values = (0..<5).map { _ in ramp.nextVolume() }
    try expect(values == [0.2, 0.4, 0.6, 0.8, 1], "渐强音量错误：\(values)")
}
test("持续提醒音量保持上限100%") {
    var ramp = SoundRamp()
    for _ in 0..<5 { _ = ramp.nextVolume() }
    for _ in 0..<1000 { try expect(ramp.nextVolume() == 1, "音量越界或降低") }
}
test("新提醒重新从低音量开始") {
    var ramp = SoundRamp()
    for _ in 0..<5 { _ = ramp.nextVolume() }
    ramp.reset()
    try expect(ramp.nextVolume() == 0.2, "新提醒沿用了高音量")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
