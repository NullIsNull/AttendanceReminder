// SPDX-License-Identifier: GPL-3.0-only
import AppKit

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let startup: LoginStartup
    private let onSave: (Preferences) throws -> Void
    private let onClose: () -> Void
    private let onMigration: () -> Void
    private let onRetry: () -> Void
    private let morning = NSDatePicker()
    private let evening = NSDatePicker()
    private let sound = NSPopUpButton(frame: .zero, pullsDown: false)
    private let increasing = NSSwitch()
    private let volume = NSSlider(value: 100, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let volumeText = NSTextField(labelWithString: "100%")
    private let login = NSSwitch()
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let migration = NSButton(title: "迁移旧版启动配置…", target: nil, action: nil)
    private let issue = NSTextField(wrappingLabelWithString: "")
    private var issueCard: NSView?
    private let feedback = NSTextField(wrappingLabelWithString: "时间和声音将在保存后生效。")
    private let reminderStatus = NSTextField(wrappingLabelWithString: "")
    private let previewAudio = ReminderAudio()
    private var preferences = Preferences()

    init(startup: LoginStartup, onSave: @escaping (Preferences) throws -> Void,
         onClose: @escaping () -> Void, onMigration: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.startup = startup
        self.onSave = onSave
        self.onClose = onClose
        self.onMigration = onMigration
        self.onRetry = onRetry
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 60)),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "AttendanceReminder 设置"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        // Window-background dragging must not intercept the slider or date controls.
        window.isMovableByWindowBackground = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("SettingsWindow does not support archives") }

    private func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
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
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func card(_ content: NSStackView) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 18
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.52)
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
        if let host = box.contentView {
            host.addSubview(content)
            Appearance.pin(content, to: host, inset: 18)
        }
        return box
    }

    private func rule() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private func row(_ name: String, _ control: NSView, detail: String? = nil) -> NSStackView {
        let title = text(name, weight: .medium)
        let labels = vertical(detail.map { [title, text($0, size: 11, secondary: true)] } ?? [title], spacing: 3)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = horizontal([labels, control], spacing: 16)
        return row
    }

    private func buildContent() {
        let surface = GlassSurface(radius: 26)
        window?.contentView = surface
        let host = surface.content
        let heading = horizontal([
            Appearance.symbol("clock.badge.checkmark", size: 34),
            vertical([text("打卡提醒", size: 25, weight: .bold),
                      text("周一至周五 · Mac 本地时间", size: 12, secondary: true)], spacing: 4)
        ], spacing: 14)

        for picker in [morning, evening] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.hourMinute]
            picker.locale = Locale(identifier: "zh_CN")
            picker.timeZone = .current
            picker.controlSize = .large
            picker.font = .monospacedDigitSystemFont(ofSize: 23, weight: .medium)
            picker.translatesAutoresizingMaskIntoConstraints = false
            picker.widthAnchor.constraint(equalToConstant: 154).isActive = true
        }
        morning.setAccessibilityLabel("上班打卡时间")
        evening.setAccessibilityLabel("下班打卡时间")
        let start = vertical([horizontal([Appearance.symbol("sun.max", size: 15), text("上班打卡", weight: .medium)], spacing: 7), morning], spacing: 10)
        let end = vertical([horizontal([Appearance.symbol("moon", size: 15), text("下班打卡", weight: .medium)], spacing: 7), evening], spacing: 10)
        let timeRow = horizontal([start, end], spacing: 28)
        timeRow.distribution = .fillEqually
        start.widthAnchor.constraint(equalTo: end.widthAnchor).isActive = true
        reminderStatus.font = .systemFont(ofSize: 12)
        reminderStatus.textColor = .secondaryLabelColor
        reminderStatus.setAccessibilityLabel("今日确认与下次提醒")
        let reminderNote = text("改时间不会重置今日确认。测试声音请点击下方“试听”。", size: 11, secondary: true)
        let timeCard = card(vertical([timeRow, rule(), reminderStatus, reminderNote], spacing: 10))
        timeRow.widthAnchor.constraint(equalTo: timeCard.widthAnchor, constant: -36).isActive = true
        reminderStatus.widthAnchor.constraint(equalTo: timeRow.widthAnchor).isActive = true
        reminderNote.widthAnchor.constraint(equalTo: timeRow.widthAnchor).isActive = true

        sound.addItems(withTitles: SoundChoice.allCases.map(\.title))
        sound.setAccessibilityLabel("提醒音效")
        sound.translatesAutoresizingMaskIntoConstraints = false
        sound.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let listen = NSButton(title: "试听", target: self, action: #selector(playPreview))
        Appearance.button(listen, symbol: "play.fill")
        let soundRow = row("提醒音效", horizontal([sound, listen], spacing: 8))
        increasing.setAccessibilityLabel("提示音逐次变大")
        increasing.toolTip = "每 30 秒播放一次，从最大音量的 20% 逐次增加到 100%。"
        let rampRow = row("提示音逐次变大", increasing, detail: "每 30 秒响一次，逐渐提高到设定音量")
        volume.target = self
        volume.action = #selector(volumeChanged)
        volume.isContinuous = true
        volume.setAccessibilityLabel("最大提示音音量")
        volume.translatesAutoresizingMaskIntoConstraints = false
        volume.widthAnchor.constraint(equalToConstant: 240).isActive = true
        volumeText.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        volumeText.alignment = .right
        volumeText.translatesAutoresizingMaskIntoConstraints = false
        volumeText.widthAnchor.constraint(equalToConstant: 42).isActive = true
        let volumeRow = row("最大音量", horizontal([volume, volumeText], spacing: 8))
        let soundRows = vertical([soundRow, rule(), rampRow, rule(), volumeRow], spacing: 14)
        for view in soundRows.arrangedSubviews { view.widthAnchor.constraint(equalTo: soundRows.widthAnchor).isActive = true }
        let soundCard = card(soundRows)

        login.target = self
        login.action = #selector(toggleLogin)
        login.setAccessibilityLabel("登录 Mac 时自动启动")
        loginStatus.font = .systemFont(ofSize: 11)
        loginStatus.textColor = .secondaryLabelColor
        let systemSettings = NSButton(title: "系统登录项…", target: self, action: #selector(openLoginSettings))
        Appearance.button(systemSettings, symbol: "arrow.up.forward.app")
        migration.target = self
        migration.action = #selector(migrateLegacy)
        Appearance.button(migration)
        let loginRow = row("登录 Mac 时自动启动", login)
        let startupRows = vertical([loginRow, loginStatus, horizontal([systemSettings, migration], spacing: 8)], spacing: 10)
        loginRow.widthAnchor.constraint(equalTo: startupRows.widthAnchor).isActive = true
        loginStatus.widthAnchor.constraint(equalTo: startupRows.widthAnchor).isActive = true
        let startupCard = card(startupRows)

        issue.font = .systemFont(ofSize: 12)
        issue.textColor = .labelColor
        issue.setAccessibilityLabel("运行状态提示")
        let retry = NSButton(title: "重试", target: self, action: #selector(retryLoading))
        Appearance.button(retry, symbol: "arrow.clockwise")
        let issueRow = horizontal([Appearance.symbol("exclamationmark.triangle", size: 18, color: .systemOrange), issue, retry])
        issueRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
        issueCard = card(vertical([issueRow]))
        issueRow.widthAnchor.constraint(equalTo: issueCard!.widthAnchor, constant: -36).isActive = true
        issueCard?.isHidden = true

        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor
        let close = NSButton(title: "关闭", target: self, action: #selector(closeSettings))
        Appearance.button(close, large: true)
        close.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存设置", target: self, action: #selector(saveSettings))
        Appearance.button(save, primary: true, symbol: "checkmark", large: true)
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = horizontal([spacer, close, save], spacing: 10)
        let footerStack = vertical([issueCard!, feedback, footer], spacing: 10)
        host.addSubview(footerStack)
        NSLayoutConstraint.activate([
            footerStack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 26),
            footerStack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -26),
            footerStack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -22)
        ])
        for view in [issueCard!, feedback, footer] {
            view.widthAnchor.constraint(equalTo: footerStack.widthAnchor).isActive = true
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = FormDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = vertical([heading, timeCard, soundCard, startupCard], spacing: 14)
        document.addSubview(stack)
        Appearance.pin(stack, to: document)
        for view in [timeCard, soundCard, startupCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        host.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: footerStack.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: footerStack.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 42),
            scroll.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -16),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
    }

    func show(preferences: Preferences) {
        if window?.isVisible != true { load(preferences) }
        window?.level = .normal
        refreshStartup()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
        feedback.stringValue = "时间和声音将在保存后生效。"
        feedback.textColor = .secondaryLabelColor
        volumeChanged()
    }

    func reload(_ value: Preferences) { load(value); refreshStartup() }

    func showIssue(_ message: String?) {
        issue.stringValue = message ?? ""
        issueCard?.isHidden = message == nil
    }

    func showReminderStatus(_ message: String, due: Bool = false) {
        reminderStatus.stringValue = message
        reminderStatus.textColor = due ? .systemOrange : .secondaryLabelColor
    }

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
        if startup.preview { loginStatus.stringValue = "预览模式，不修改系统登录项。" }
        else if startup.hasLegacyAgent { loginStatus.stringValue = "检测到旧版启动配置。迁移后可开启登录启动，打卡记录保留。" }
        else { loginStatus.stringValue = startup.status.description + " 此开关即时生效。" }
    }

    @objc private func volumeChanged() { volumeText.stringValue = "\(Int(volume.doubleValue.rounded()))%" }

    @objc private func playPreview() {
        previewAudio.stop()
        previewAudio.play(SoundChoice.allCases[sound.indexOfSelectedItem], volume: Float(volume.doubleValue / 100))
    }

    @objc private func saveSettings() {
        guard window?.makeFirstResponder(nil) != false else { return }
        do {
            let value = try candidate()
            try onSave(value)
            preferences = value
            window?.close()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func closeSettings() { window?.close() }
    @objc private func retryLoading() { onRetry() }

    @objc private func toggleLogin() {
        do { try startup.setEnabled(login.state == .on) }
        catch { showError(error.localizedDescription) }
        refreshStartup()
    }

    @objc private func openLoginSettings() { startup.openSystemSettings() }

    @objc private func migrateLegacy() {
        guard let window = window else { return }
        let alert = Appearance.alert(title: "迁移旧版启动配置？",
            message: "停止旧版后台服务并备份旧配置，保留打卡确认记录。迁移后可开启登录启动。",
            symbol: "arrow.triangle.2.circlepath")
        alert.addButton(withTitle: "迁移")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self = self, result == .alertFirstButtonReturn else { return }
            do { try self.startup.migrateLegacyAgent(); self.onMigration() }
            catch { self.showError(error.localizedDescription) }
            self.refreshStartup()
        }
    }

    private func showError(_ message: String) {
        feedback.stringValue = "未保存：\(message)"
        feedback.textColor = .systemRed
        NSAccessibility.post(element: feedback, notification: .valueChanged)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    func windowDidBecomeKey(_ notification: Notification) { refreshStartup() }
    func windowWillClose(_ notification: Notification) { previewAudio.stop(); onClose() }
}
