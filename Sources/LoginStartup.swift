// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ServiceManagement

final class LoginStartup {
    let preview: Bool
    let legacyURL: URL

    init(preview: Bool, legacyURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/local.clockin.reminder.plist")) {
        self.preview = preview
        self.legacyURL = legacyURL
    }

    var hasLegacyAgent: Bool { !preview && FileManager.default.fileExists(atPath: legacyURL.path) }

    var status: StartupStatus {
        if preview { return .disabled }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    func setEnabled(_ enabled: Bool) throws {
        guard !preview else { throw ReminderError.system("预览不会修改登录启动。") }
        guard !hasLegacyAgent else { throw ReminderError.system("先迁移旧版启动配置，再使用登录启动开关。") }
        if enabled {
            guard isInstalled else { throw ReminderError.system("先把 AttendanceReminder 拖入“应用程序”，从那里打开后再开启。") }
            if status == .disabled || status == .unavailable { try SMAppService.mainApp.register() }
        } else if status.isRequested {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() { if !preview { SMAppService.openSystemSettingsLoginItems() } }

    func migrateLegacyAgent() throws {
        guard hasLegacyAgent else { return }
        _ = try LegacyConfiguration.times(from: Data(contentsOf: legacyURL))
        let service = "gui/\(getuid())/local.clockin.reminder"
        let probe = try launchctl(["print", service])
        if probe.code == 0 {
            if probe.output.components(separatedBy: .newlines).contains(where: {
                $0.trimmingCharacters(in: .whitespaces) == "pid = \(getpid())"
            }) {
                throw ReminderError.system("当前进程由旧服务启动。先退出旧版，再从“应用程序”打开新版迁移。")
            }
            let stop = try launchctl(["bootout", service])
            guard stop.code == 0 else { throw ReminderError.system("停止旧版服务失败：\(stop.output)") }
        }
        let backup = legacyURL.deletingLastPathComponent()
            .appendingPathComponent("local.clockin.reminder.plist.disabled-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: legacyURL, to: backup)
    }

    private func launchctl(_ arguments: [String]) throws -> (code: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
