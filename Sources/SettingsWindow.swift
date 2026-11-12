// SPDX-License-Identifier: GPL-3.0-only
import AppKit

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let startup: LoginStartup
    private let onSave: (Preferences) throws -> Void
    private let onClose: () -> Void
    private let onMigration: () -> Void
    private let morning = NSDatePicker()
    private let evening = NSDatePicker()
    private let sound = NSPopUpButton(frame: .zero, pullsDown: false)
    private let increasing = NSButton(checkboxWithTitle: "提示音逐次变大", target: nil, action: nil)
    private let volume = NSSlider(value: 100, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let volumeText = NSTextField(labelWithString: "100%")
    private let login = NSButton(checkboxWithTitle: "登录 Mac 时自动启动", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let migration = NSButton(title: "迁移旧版启动配置…", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "设置保存在本机，关闭窗口后继续在菜单栏运行。")
    private let previewAudio = ReminderAudio()
    private var preferences = Preferences()

    init(startup: LoginStartup, onSave: @escaping (Preferences) throws -> Void,
         onClose: @escaping () -> Void, onMigration: @escaping () -> Void) {
        self.startup = startup
        self.onSave = onSave
        self.onClose = onClose
        self.onMigration = onMigration
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AttendanceReminder 设置"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("SettingsWindow does not support archives") }

    private func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func vertical(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func card(_ title: String, _ views: [NSView]) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 12
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
        let content = vertical([text(title, size: 15, weight: .semibold)] + views)
        box.contentView?.addSubview(content)
        if let host = box.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18),
                content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
                content.topAnchor.constraint(equalTo: host.topAnchor, constant: 15),
                content.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -15)
            ])
        }
        return box
    }

    private func buildContent() {
        guard let host = window?.contentView else { return }
        let title = text("打卡提醒", size: 26, weight: .bold)
        let subtitle = text("周一至周五 · 使用 Mac 当前时区")
        subtitle.textColor = .secondaryLabelColor
        let heading = vertical([title, subtitle], spacing: 5)
        for picker in [morning, evening] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.hourMinute]
            picker.locale = Locale(identifier: "zh_CN")
            picker.timeZone = .current
            picker.controlSize = .large
            picker.translatesAutoresizingMaskIntoConstraints = false
            picker.widthAnchor.constraint(equalToConstant: 125).isActive = true
        }
        morning.setAccessibilityLabel("上班打卡时间")
        evening.setAccessibilityLabel("下班打卡时间")
        let timeRow = horizontal([text("上班打卡"), morning, text("下班打卡"), evening], spacing: 20)
        let timeCard = card("打卡时间", [timeRow])

        sound.addItems(withTitles: SoundChoice.allCases.map(\.title))
        sound.setAccessibilityLabel("提醒音效")
        sound.translatesAutoresizingMaskIntoConstraints = false
        sound.widthAnchor.constraint(equalToConstant: 255).isActive = true
        let listen = NSButton(title: "试听", target: self, action: #selector(playPreview))
        listen.bezelStyle = .rounded
        let soundRow = horizontal([sound, listen])
        increasing.toolTip = "每 30 秒播放一次，从最大音量的 20% 逐次增加到 100%。"
        volume.target = self
        volume.action = #selector(volumeChanged)
        volume.setAccessibilityLabel("最大提示音音量")
        volume.translatesAutoresizingMaskIntoConstraints = false
        volume.widthAnchor.constraint(equalToConstant: 270).isActive = true
        volumeText.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        volumeText.translatesAutoresizingMaskIntoConstraints = false
        volumeText.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let volumeRow = horizontal([text("最大音量"), volume, volumeText])
        let soundCard = card("提示音", [soundRow, increasing, volumeRow])

        login.target = self
        login.action = #selector(toggleLogin)
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.translatesAutoresizingMaskIntoConstraints = false
        loginStatus.widthAnchor.constraint(equalToConstant: 545).isActive = true
        let systemSettings = NSButton(title: "打开系统登录项…", target: self, action: #selector(openLoginSettings))
        systemSettings.bezelStyle = .rounded
        migration.target = self
        migration.action = #selector(migrateLegacy)
        migration.bezelStyle = .rounded
        let startupCard = card("启动方式", [login, loginStatus, horizontal([systemSettings, migration])])

        let save = NSButton(title: "保存设置", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.keyEquivalent = "\r"
        save.bezelColor = .controlAccentColor
        save.translatesAutoresizingMaskIntoConstraints = false
        save.widthAnchor.constraint(equalToConstant: 105).isActive = true
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
        let footer = horizontal([feedback, save], spacing: 24)
        let stack = vertical([heading, timeCard, soundCard, startupCard, footer], spacing: 16)
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 20)
        ])
        for view in [timeCard, soundCard, startupCard, footer] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func show(preferences: Preferences, aboveReminder: Bool) {
        if window?.isVisible != true { load(preferences) }
        setAboveReminder(aboveReminder)
        refreshStartup()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func setAboveReminder(_ enabled: Bool) {
        window?.level = enabled ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) : .normal
    }

    private func load(_ value: Preferences) {
        preferences = value
        let calendar = Schedule.calendar()
        morning.timeZone = calendar.timeZone
        evening.timeZone = calendar.timeZone
        morning.dateValue = calendar.date(bySettingHour: value.times.morning.hour,
            minute: value.times.morning.minute, second: 0, of: Date())!
        evening.dateValue = calendar.date(bySettingHour: value.times.evening.hour,
            minute: value.times.evening.minute, second: 0, of: Date())!
        sound.selectItem(at: SoundChoice.allCases.firstIndex(of: value.sound) ?? 0)
        increasing.state = value.increasingVolume ? .on : .off
        volume.doubleValue = value.maximumVolume * 100
        volumeChanged()
    }

    func reload(_ value: Preferences) { load(value); refreshStartup() }

    private func candidate() throws -> Preferences {
        let calendar = Schedule.calendar()
        func time(_ picker: NSDatePicker) -> String {
            String(format: "%02d:%02d", calendar.component(.hour, from: picker.dateValue),
                   calendar.component(.minute, from: picker.dateValue))
        }
        var value = preferences
        value.morning = time(morning)
        value.evening = time(evening)
        value.sound = SoundChoice.allCases[sound.indexOfSelectedItem]
        value.increasingVolume = increasing.state == .on
        value.maximumVolume = volume.doubleValue / 100
        return try value.validated()
    }

    func refreshStartup() {
        login.state = startup.status.isRequested ? .on : .off
        login.isEnabled = !startup.preview && !startup.hasLegacyAgent
        migration.isHidden = !startup.hasLegacyAgent
        if startup.preview { loginStatus.stringValue = "界面预览，不修改系统登录项。" }
        else if startup.hasLegacyAgent { loginStatus.stringValue = "检测到旧版启动配置，请先迁移，保留打卡确认记录。" }
        else { loginStatus.stringValue = startup.status.description + " 此开关即时生效。" }
    }

    @objc private func volumeChanged() { volumeText.stringValue = "\(Int(volume.doubleValue.rounded()))%" }

    @objc private func playPreview() {
        previewAudio.stop()
        previewAudio.play(SoundChoice.allCases[sound.indexOfSelectedItem], volume: Float(volume.doubleValue / 100))
    }

    @objc private func saveSettings() {
        do {
            let value = try candidate()
            try onSave(value)
            preferences = value
            window?.close()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func toggleLogin() {
        do { try startup.setEnabled(login.state == .on) }
        catch { showError(error.localizedDescription) }
        refreshStartup()
    }

    @objc private func openLoginSettings() { startup.openSystemSettings() }

    @objc private func migrateLegacy() {
        let alert = NSAlert()
        alert.messageText = "迁移旧版启动配置？"
        alert.informativeText = "停止旧版后台服务并备份旧配置，保留打卡确认记录。迁移后可在这里开启登录启动。"
        alert.addButton(withTitle: "迁移")
        alert.addButton(withTitle: "取消")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try startup.migrateLegacyAgent(); onMigration() }
        catch { showError(error.localizedDescription) }
        refreshStartup()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "设置未完成"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        alert.runModal()
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshStartup() }
    func windowWillClose(_ notification: Notification) { previewAudio.stop(); onClose() }
}
