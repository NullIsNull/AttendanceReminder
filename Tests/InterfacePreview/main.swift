// SPDX-License-Identifier: GPL-3.0-only
// Dedicated QA executable: never shipped in the application bundle.
import AppKit

let configuration = Bundle.main.infoDictionary ?? [:]
guard let path = configuration["TestStateDirectory"] as? String, path.hasPrefix("/"),
      path != StateStore.defaultDirectory.path else { fatalError("Provide an isolated TestStateDirectory") }
let directory = URL(fileURLWithPath: path)
let mode = configuration["TestMode"] as? String ?? "settings"
let store = try StateStore(directory: directory)
final class RecordingAudio: ReminderSoundPlaying {
    var plays: [[String: Any]] = []
    private let audio = ReminderAudio()
    func play(_ choice: SoundChoice, volume: Float) {
        plays.append(["time": Date().ISO8601Format(), "volume": volume, "sound": choice.rawValue])
        audio.play(choice, volume: volume)
    }
    func stop() { audio.stop() }
}
let recordingAudio = RecordingAudio()
if try store.loadPreferences() == nil {
    var preferences = Preferences()
    preferences.morning = "23:58"
    preferences.evening = "23:59"
    let now = Date()
    let calendar = Schedule.calendar()
    var state = try store.loadOrCreate(now: now, calendar: calendar)
    if mode == "due" || mode == "confirmed" {
        let nextMinute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        guard (2...6).contains(calendar.component(.weekday, from: now)),
              calendar.component(.hour, from: now) < 23 else { fatalError("Run the due fixture on a weekday before 23:00") }
        preferences.morning = String(format: "%02d:%02d", calendar.component(.hour, from: nextMinute), calendar.component(.minute, from: nextMinute))
        preferences.maximumVolume = 0.3
        if mode == "confirmed" {
            let day = Schedule.dayKey(now, calendar: calendar)
            let event = ReminderEvent(day: day, slot: .morning, scheduledAt: now, timeZone: calendar.timeZone.identifier)
            try store.confirm(event, at: now, state: &state)
        }
    }
    try store.savePreferences(preferences)
}
// A second file descriptor reproduces the same exclusion as another process.
let blocker = mode == "conflict" ? try InstanceLock(directory: directory) : nil
let application = NSApplication.shared
if configuration["TestDarkAppearance"] as? Bool == true { application.appearance = NSAppearance(named: .darkAqua) }
let delegate = ReminderApplication(directory: directory, preview: mode == "reminder", silent: mode != "due" && mode != "confirmed",
    autoExit: nil, times: nil, settingsPreview: false, openSettingsAtLaunch: mode != "reminder",
    startup: LoginStartup(preview: true), audio: recordingAudio)
application.delegate = delegate
let snapshotURL = directory.deletingLastPathComponent().appendingPathComponent("status-\(mode).json")
let observer = Timer(timeInterval: 0.25, repeats: true) { _ in
    let snapshot: [String: Any] = [
        "settingsVisible": application.windows.contains { $0.title == "AttendanceReminder 设置" && $0.isVisible },
        "reminderWindows": application.windows.filter { $0 is ReminderPanel && $0.isVisible }.count,
        "audioPlays": recordingAudio.plays
    ]
    if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: .sortedKeys) {
        try? data.write(to: snapshotURL, options: .atomic)
    }
}
RunLoop.main.add(observer, forMode: .common)
DispatchQueue.main.asyncAfter(deadline: .now() + 300) { application.terminate(nil) }
withExtendedLifetime(blocker) { application.run() }
