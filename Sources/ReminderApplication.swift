// SPDX-License-Identifier: GPL-3.0-only
import AppKit

final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class BackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.07, green: 0.12, blue: 0.23, alpha: 1),
                   ending: NSColor(srgbRed: 0.035, green: 0.055, blue: 0.11, alpha: 1))?
            .draw(in: bounds, angle: -25)
    }
}

final class ReminderApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let directory: URL
    let preview: Bool
    let silent: Bool
    let autoExit: TimeInterval?
    let initialTimes: ReminderTimes?
    let settingsPreview: Bool
    let openSettingsAtLaunch: Bool
    private var preferences = Preferences()
    private var times: ReminderTimes { preferences.times }
    private var pausedUntil: Date?
    private var awaitingSetup = false
    private var settingsController: SettingsWindow?
    private var scheduleItem: NSMenuItem?
    private var summaryItem: NSMenuItem?
    private var resumeItem: NSMenuItem?
    private lazy var startup = LoginStartup(preview: preview || settingsPreview)
    private var store: StateStore?
    private var instanceLock: InstanceLock?
    private var state: ReminderState?
    private var statusItem: NSStatusItem?
    private var panels: [ReminderPanel] = []
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var keyMonitor: Any?
    private var event: ReminderEvent?
    private var displayedID: String?
    private var lastSound: Date?
    private var problem: String?
    private var dialogOpen = false
    private var previewFinished = false
    private let audio = ReminderAudio()
    private var soundRamp = SoundRamp()

    init(directory: URL, preview: Bool, silent: Bool, autoExit: TimeInterval?, times: ReminderTimes?, settingsPreview: Bool, openSettingsAtLaunch: Bool) {
        self.directory = directory
        self.preview = preview
        self.silent = silent
        self.autoExit = autoExit
        self.initialTimes = times
        self.settingsPreview = settingsPreview
        self.openSettingsAtLaunch = openSettingsAtLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !preview && !settingsPreview { loadState() }
        else {
            if preview, FileManager.default.fileExists(atPath: directory.appendingPathComponent("preferences.json").path),
               let previewStore = try? StateStore(directory: directory), let saved = try? previewStore.loadPreferences() {
                preferences = saved
            }
            if let initialTimes = initialTimes {
                preferences.morning = initialTimes.morning.text
                preferences.evening = initialTimes.evening.text
            }
        }
        configureMenu()
        configureObservers()
        if awaitingSetup || settingsPreview || openSettingsAtLaunch || startup.hasLegacyAgent { showSettings() }
        tick()
        timer = Timer(timeInterval: 5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer?.tolerance = 0.5
        RunLoop.main.add(timer!, forMode: .common)
        if let seconds = autoExit, preview || settingsPreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
    }

    private func loadState() {
        do {
            if store == nil { store = try StateStore(directory: directory) }
            let savedPreferences = try store?.loadPreferences()
            if let saved = savedPreferences { preferences = saved }
            else if startup.hasLegacyAgent {
                let legacyTimes = try LegacyConfiguration.times(from: Data(contentsOf: startup.legacyURL))
                preferences.morning = legacyTimes.morning.text
                preferences.evening = legacyTimes.evening.text
            }
            if let initialTimes = initialTimes {
                preferences.morning = initialTimes.morning.text
                preferences.evening = initialTimes.evening.text
            }
            if instanceLock == nil { instanceLock = try InstanceLock(directory: directory) }
            state = try store?.loadOrCreate(now: Date(), calendar: Schedule.calendar())
            try store?.savePreferences(preferences)
            pausedUntil = try store?.activePause(now: Date())
            awaitingSetup = savedPreferences == nil
            problem = nil
        } catch ReminderError.alreadyRunning {
            let modernInstance = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.clockin.reminder")
                .first { app in
                    guard app.processIdentifier != getpid(), let url = app.bundleURL,
                          let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return false }
                    return version.compare("2.0", options: .numeric) != .orderedAscending
                }
            if modernInstance != nil {
                DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.clockin.reminder.showSettings"), object: directory.path)
                exit(0)
            }
            problem = "旧版提醒程序仍在运行。先从旧版菜单栏退出，再点击“重试读取记录”；若有旧版启动配置，可从设置中迁移。"
        } catch {
            problem = error.localizedDescription
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        scheduleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        summaryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        scheduleItem?.isEnabled = false
        summaryItem?.isEnabled = false
        menu.addItem(scheduleItem!)
        menu.addItem(summaryItem!)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        addMenuItem("显示提醒 / 今日状态", action: #selector(showStatus), to: menu)
        addMenuItem("演示提醒（不写记录）", action: #selector(startPreview), to: menu)
        addMenuItem("使用说明", action: #selector(openGuide), to: menu)
        addMenuItem("打开确认记录文件夹", action: #selector(openRecords), to: menu)
        menu.addItem(.separator())
        addMenuItem("暂停 15 分钟", action: #selector(pauseReminders), to: menu)
        resumeItem = NSMenuItem(title: "立即恢复提醒", action: #selector(resumeReminders), keyEquivalent: "")
        resumeItem?.target = self
        menu.addItem(resumeItem!)
        let quit = NSMenuItem(title: "紧急退出…", action: #selector(emergencyExit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: "打卡提醒")
            ?? NSImage(systemSymbolName: "clock", accessibilityDescription: "打卡提醒")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = icon
        statusItem?.button?.setAccessibilityLabel("打卡提醒")
        statusItem?.menu = menu
        updateStatusTitle(calendar: Schedule.calendar(), now: Date())

        let mainMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(root)
        NSApp.mainMenu = mainMenu
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] input in
            guard let self = self else { return input }
            let flags = input.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if input.charactersIgnoringModifiers?.lowercased() == "q", flags.contains(.command) {
                self.emergencyExit()
                return nil
            }
            if !self.panels.isEmpty && !self.dialogOpen && self.settingsController?.window?.isKeyWindow != true {
                if input.keyCode == 53 { return nil }
                if flags.contains(.command), ["w", "m", "h"].contains(input.charactersIgnoringModifiers?.lowercased() ?? "") {
                    return nil
                }
            }
            return input
        }
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, rebuild: Bool = false) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if rebuild { self.displayedID = nil }
            self.tick()
        }
        observers.append((center, token))
    }

    private func configureObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didWakeNotification, center: workspace, rebuild: true)
        observe(NSWorkspace.screensDidWakeNotification, center: workspace, rebuild: true)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspace, rebuild: true)
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: workspace)
        observe(NSApplication.didChangeScreenParametersNotification, center: .default, rebuild: true)
        observe(.NSSystemTimeZoneDidChange, center: .default, rebuild: true)
        observe(.NSSystemClockDidChange, center: .default, rebuild: true)
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: Notification.Name("local.clockin.reminder.showSettings"), object: directory.path, queue: .main) { [weak self] _ in
            self?.showSettings()
        }
        observers.append((center, token))
    }

    @objc private func tick() {
        guard !dialogOpen, !previewFinished else { return }
        let now = Date()
        let calendar = Schedule.calendar()
        if settingsController?.window?.isVisible == true { settingsController?.refreshStartup() }
        if settingsPreview || awaitingSetup { return }
        if let until = pausedUntil, until > now {
            closePanels()
            event = nil
            displayedID = nil
            lastSound = nil
            soundRamp.reset()
            updateStatusTitle(calendar: calendar, now: now)
            return
        }
        pausedUntil = nil
        if let problem = problem {
            if displayedID != "error:\(problem)" {
                showPanels(title: "确认记录需要处理", time: "保存未完成", detail: problem,
                           footer: "原记录不会被覆盖。修复文件或权限后重试。", error: true)
                displayedID = "error:\(problem)"
            }
            return
        }
        let pending = state.map { Schedule.pending(state: $0, now: now, calendar: calendar, times: times) } ?? []
        let next: ReminderEvent?
        if preview {
            let day = Schedule.dayKey(now, calendar: calendar)
            next = ReminderEvent(day: day, slot: .morning, scheduledAt: now, timeZone: calendar.timeZone.identifier)
        } else {
            next = pending.first
        }
        guard let next = next else {
            event = nil
            displayedID = nil
            closePanels()
            lastSound = nil
            soundRamp.reset()
            updateStatusTitle(calendar: calendar, now: now)
            return
        }
        if event?.id != next.id {
            lastSound = nil
            soundRamp.reset()
        }
        event = next
        let identifier = "\(next.id)/\(next.timeZone)/\(pending.count)"
        if displayedID != identifier {
            let missed = next.day != Schedule.dayKey(now, calendar: calendar) ? "历史补提醒 · " : ""
            let title = preview ? "提醒演示 · 上班打卡" : "\(missed)\(next.slot.title)"
            let detail = "\(next.day)  ·  \(next.timeZone)\n请先完成公司考勤打卡，再点击下方按钮。"
            let footer = preview ? "演示不会生成确认记录。" : "本机确认不等于考勤提交。还有 \(pending.count) 项待确认。"
            showPanels(title: title, time: times.time(for: next.slot).text, detail: detail, footer: footer, error: false)
            displayedID = identifier
        }
        if !dialogOpen {
            for panel in panels { panel.orderFrontRegardless() }
        }
        if !silent && (lastSound == nil || now.timeIntervalSince(lastSound!) >= 30) {
            let volume = (preferences.increasingVolume ? soundRamp.nextVolume() : 1) * Float(preferences.maximumVolume)
            audio.play(preferences.sound, volume: volume)
            lastSound = now
        }
        updateStatusTitle(calendar: calendar, now: now)
        summaryItem?.title = preview ? "正在演示提醒" : "还有 \(pending.count) 项待确认"
        settingsController?.setAboveReminder(!panels.isEmpty)
    }

    private func updateStatusTitle(calendar: Calendar, now: Date) {
        let day = Schedule.dayKey(now, calendar: calendar)
        let count = PunchSlot.allCases.filter { state?.confirmations["\(day)/\($0.rawValue)"] != nil }.count
        let weekday = (2...6).contains(calendar.component(.weekday, from: now))
        scheduleItem?.title = "工作日 · \(times.morning.text) / \(times.evening.text)"
        summaryItem?.title = weekday ? "今日已确认 \(count)/2" : "周末不产生新提醒"
        if let until = pausedUntil, until > now {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            summaryItem?.title = "已暂停，\(formatter.string(from: until)) 恢复"
        }
        resumeItem?.isEnabled = pausedUntil != nil
        statusItem?.button?.toolTip = "打卡提醒 · \(summaryItem?.title ?? "") · \(times.morning.text) / \(times.evening.text)"
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        field.maximumNumberOfLines = 0
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func showPanels(title: String, time: String, detail: String, footer: String, error: Bool) {
        closePanels()
        let accent = NSColor(srgbRed: 0.44, green: 0.78, blue: 1, alpha: 1)
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let width = min(860, max(380, visible.width - 48))
            let height = min(550, max(400, visible.height - 48))
            let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
            let panel = ReminderPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "打卡提醒"
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.delegate = self
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.animationBehavior = .none
            panel.setAccessibilityLabel(title)
            let background = BackgroundView(frame: NSRect(origin: .zero, size: frame.size))
            background.wantsLayer = true
            background.layer?.cornerRadius = 24
            background.layer?.masksToBounds = true
            panel.contentView = background

            let heading = label(title, size: 23, color: accent, weight: .semibold)
            let clock = label(time, size: error ? 43 : 84, color: .white, weight: .bold)
            let body = label(detail, size: 18, color: NSColor(white: 0.87, alpha: 1))
            let note = label(footer, size: 13, color: NSColor(white: 0.68, alpha: 1))
            let dragHint = label("可拖动窗口顶部，移开后操作考勤页面", size: 12, color: NSColor(white: 0.58, alpha: 1))
            let confirm = NSButton(title: error ? "重试读取记录" : "已打卡", target: self,
                                   action: error ? #selector(retryLoading) : #selector(confirmPunch))
            confirm.bezelStyle = .rounded
            confirm.controlSize = .large
            confirm.font = .systemFont(ofSize: 23, weight: .semibold)
            confirm.bezelColor = accent
            confirm.contentTintColor = .black
            confirm.translatesAutoresizingMaskIntoConstraints = false
            // 不把回车设为默认确认键，避免窗口出现时吞掉其他应用的回车。
            confirm.keyEquivalent = ""
            let emergency = NSButton(title: preview ? "退出演示" : "暂停 15 分钟",
                                     target: self, action: preview ? #selector(emergencyExit) : #selector(pauseReminders))
            emergency.bezelStyle = .rounded
            emergency.controlSize = .regular
            emergency.translatesAutoresizingMaskIntoConstraints = false
            let stack = NSStackView(views: [heading, clock, body, confirm, note, emergency, dragHint])
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
                stack.widthAnchor.constraint(equalTo: background.widthAnchor, constant: -64),
                heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
                body.widthAnchor.constraint(equalTo: stack.widthAnchor),
                note.widthAnchor.constraint(equalTo: stack.widthAnchor),
                confirm.widthAnchor.constraint(equalToConstant: 270),
                confirm.heightAnchor.constraint(equalToConstant: 60)
            ])
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let target = panels.first { $0.screen == NSScreen.main } ?? panels.first
        target?.makeKeyAndOrderFront(nil)
        settingsController?.setAboveReminder(true)
        if settingsController?.window?.isVisible == true { settingsController?.window?.makeKeyAndOrderFront(nil) }
    }

    private func closePanels() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        audio.stop()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    @objc private func confirmPunch() {
        guard !dialogOpen, problem == nil else { return }
        if preview {
            previewFinished = true
            closePanels()
            NSApp.terminate(nil)
            return
        }
        guard let event = event, var candidate = state, let store = store else { return }
        do {
            try store.confirm(event, at: Date(), state: &candidate)
            state = candidate
            displayedID = nil
            tick()
        } catch {
            showAlert(title: "确认未保存", text: "\(error.localizedDescription)\n窗口会保留，保存成功后才算确认。")
        }
    }

    @objc private func retryLoading() {
        loadState()
        displayedID = nil
        if awaitingSetup { showSettings() }
        tick()
    }

    @objc private func emergencyExit() {
        guard !dialogOpen else { return }
        if preview || settingsPreview { NSApp.terminate(nil); return }
        let alert = makeAlert(title: "退出打卡提醒？",
            text: "退出不会记作已打卡。退出后不再提醒，直到你再次打开应用；开启登录启动后，下次登录也会恢复。临时离开可选择“暂停 15 分钟”。")
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "退出程序")
        dialogOpen = true
        let result = alert.runModal()
        dialogOpen = false
        guard result == .alertSecondButtonReturn else { return }
        NSApp.terminate(nil)
    }

    private func makeAlert(title: String, text: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        return alert
    }

    private func showAlert(title: String, text: String) {
        let alert = makeAlert(title: title, text: text)
        alert.addButton(withTitle: "知道了")
        dialogOpen = true
        alert.runModal()
        dialogOpen = false
    }

    @objc private func showStatus() {
        tick()
        if !panels.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            panels.first?.makeKeyAndOrderFront(nil)
            return
        }
        let calendar = Schedule.calendar()
        let day = Schedule.dayKey(Date(), calendar: calendar)
        let rows = PunchSlot.allCases.map { slot -> String in
            let confirmed = state?.confirmations["\(day)/\(slot.rawValue)"] != nil
            return "\(slot.title) \(times.time(for: slot).text)：\(confirmed ? "已确认" : "未确认")"
        }
        showAlert(title: "今日打卡确认", text: "\(day) · \(calendar.timeZone.identifier)\n\(rows.joined(separator: "\n"))\n仅周一至周五生成提醒。")
    }

    @objc private func startPreview() {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = times.arguments + ["--preview", "--state-dir", directory.path]
        do { try process.run() } catch { showAlert(title: "无法启动演示", text: error.localizedDescription) }
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindow(startup: startup, onSave: { [weak self] value in
                guard let self = self else { return }
                if !self.settingsPreview && !self.preview {
                    guard self.instanceLock != nil, let store = self.store else {
                        throw ReminderError.system("请先退出旧版提醒程序或完成迁移，再保存设置。")
                    }
                    try store.savePreferences(value)
                }
                self.preferences = value
                self.awaitingSetup = false
                self.event = nil
                self.displayedID = nil
                self.lastSound = nil
                self.soundRamp.reset()
                self.audio.stop()
            }, onClose: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.awaitingSetup = false
                    if self.settingsPreview { NSApp.terminate(nil) }
                    else { self.tick() }
                }
            }, onMigration: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.loadState()
                    if let self = self { self.settingsController?.reload(self.preferences) }
                    self?.awaitingSetup = false
                    self?.displayedID = nil
                    self?.tick()
                }
            })
        }
        settingsController?.show(preferences: preferences, aboveReminder: !panels.isEmpty)
    }

    @objc private func pauseReminders() {
        if preview || settingsPreview { NSApp.terminate(nil); return }
        do {
            let until = Date().addingTimeInterval(15 * 60)
            guard instanceLock != nil, let store = store else {
                throw ReminderError.system("记录目录尚未就绪，或旧版仍在运行。可使用菜单栏的紧急退出。")
            }
            try store.pause(until: until, now: Date())
            pausedUntil = until
            tick()
        } catch { showAlert(title: "暂停未保存", text: error.localizedDescription) }
    }

    @objc private func resumeReminders() {
        do {
            guard instanceLock != nil, let store = store else {
                throw ReminderError.system("记录目录尚未就绪，或旧版仍在运行。")
            }
            try store.clearPause()
            pausedUntil = nil
            lastSound = nil
            tick()
        } catch { showAlert(title: "恢复失败", text: error.localizedDescription) }
    }

    @objc private func openGuide() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "md", subdirectory: "Support/docs") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func openRecords() {
        NSWorkspace.shared.open(directory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        audio.stop()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        for (center, token) in observers { center.removeObserver(token) }
        closePanels()
    }
}
