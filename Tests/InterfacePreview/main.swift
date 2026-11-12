// SPDX-License-Identifier: GPL-3.0-only
// Dedicated QA executable: never shipped in the application bundle.
import AppKit

let configuration = Bundle.main.infoDictionary ?? [:]
guard let path = configuration["TestStateDirectory"] as? String, path.hasPrefix("/"),
      path != StateStore.defaultDirectory.path else { fatalError("Provide an isolated TestStateDirectory") }
let directory = URL(fileURLWithPath: path)
let mode = configuration["TestMode"] as? String ?? "settings"
let store = try StateStore(directory: directory)
if try store.loadPreferences() == nil {
    var preferences = Preferences()
    preferences.morning = "23:58"
    preferences.evening = "23:59"
    try store.savePreferences(preferences)
    _ = try store.loadOrCreate(now: Date(), calendar: Schedule.calendar())
}
// A second file descriptor reproduces the same exclusion as another process.
let blocker = mode == "conflict" ? try InstanceLock(directory: directory) : nil
let application = NSApplication.shared
if configuration["TestDarkAppearance"] as? Bool == true { application.appearance = NSAppearance(named: .darkAqua) }
let delegate = ReminderApplication(directory: directory, preview: mode == "reminder", silent: true,
    autoExit: nil, times: nil, settingsPreview: false, openSettingsAtLaunch: mode != "reminder",
    startup: LoginStartup(preview: true))
application.delegate = delegate
let snapshotURL = directory.deletingLastPathComponent().appendingPathComponent("status-\(mode).json")
let observer = Timer(timeInterval: 0.25, repeats: true) { _ in
    let snapshot: [String: Any] = [
        "settingsVisible": application.windows.contains { $0.title == "AttendanceReminder 设置" && $0.isVisible },
        "reminderWindows": application.windows.filter { $0 is ReminderPanel && $0.isVisible }.count
    ]
    if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: .sortedKeys) {
        try? data.write(to: snapshotURL, options: .atomic)
    }
}
RunLoop.main.add(observer, forMode: .common)
DispatchQueue.main.asyncAfter(deadline: .now() + 300) { application.terminate(nil) }
withExtendedLifetime(blocker) { application.run() }
