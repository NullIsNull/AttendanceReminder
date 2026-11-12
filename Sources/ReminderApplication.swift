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
    let times: ReminderTimes
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
    private var sound: NSSound?
    private var fallbackSound: NSSound?
    private var soundRamp = SoundRamp()

    init(directory: URL, preview: Bool, silent: Bool, autoExit: TimeInterval?, times: ReminderTimes) {
        self.directory = directory
        self.preview = preview
        self.silent = silent
        self.autoExit = autoExit
        self.times = times
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        configureObservers()
        sound = NSSound(named: NSSound.Name("Ping"))
        if let url = Bundle.main.url(forResource: "reminder", withExtension: "wav") {
            fallbackSound = NSSound(contentsOf: url, byReference: false)
        }
        if !preview { loadState() }
        tick()
        timer = Timer(timeInterval: 5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer?.tolerance = 0.5
        RunLoop.main.add(timer!, forMode: .common)
        if let seconds = autoExit, preview {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
    }

    private func loadState() {
        do {
            if store == nil { store = try StateStore(directory: directory) }
            if instanceLock == nil { instanceLock = try InstanceLock(directory: directory) }
            if let until = try store?.activePause(now: Date()) {
                fputs("紧急暂停中，恢复时间：\(until.ISO8601Format())\n", stderr)
                exit(0)
            }
            state = try store?.loadOrCreate(now: Date(), calendar: Schedule.calendar())
            problem = nil
        } catch ReminderError.alreadyRunning {
            fputs("程序已在运行。新参数不会改变现有进程；先紧急退出，再重新启动或更新安装。\n", stderr)
            exit(0)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "周一至周五 · \(times.morning.text) / \(times.evening.text)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addMenuItem("显示提醒 / 今日状态", action: #selector(showStatus), to: menu)
        addMenuItem("演示提醒（不写记录）", action: #selector(startPreview), to: menu)
        addMenuItem("打开确认记录文件夹", action: #selector(openRecords), to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "紧急退出（暂停 15 分钟）…", action: #selector(emergencyExit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command, .control, .option]
        quit.target = self
        menu.addItem(quit)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = preview ? "打卡演示" : "打卡"
        statusItem?.button?.toolTip = "工作日 \(times.morning.text) 和 \(times.evening.text) 打卡提醒"
        statusItem?.menu = menu

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
            if !self.panels.isEmpty && !self.dialogOpen {
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
    }

    @objc private func tick() {
        guard !dialogOpen, !previewFinished else { return }
        let now = Date()
        let calendar = Schedule.calendar()
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
            let volume = soundRamp.nextVolume()
            sound?.volume = volume
            if sound?.play() != true {
                fallbackSound?.volume = volume
                if fallbackSound?.play() != true { fputs("提示音播放失败，窗口提醒继续显示。\n", stderr) }
            }
            lastSound = now
        }
        statusItem?.button?.title = preview ? "打卡演示" : "打卡 · 待确认"
    }

    private func updateStatusTitle(calendar: Calendar, now: Date) {
        let day = Schedule.dayKey(now, calendar: calendar)
        let count = PunchSlot.allCases.filter { state?.confirmations["\(day)/\($0.rawValue)"] != nil }.count
        let weekday = (2...6).contains(calendar.component(.weekday, from: now))
        statusItem?.button?.title = weekday ? "打卡 \(count)/2" : "打卡 · 周末"
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
            let emergency = NSButton(title: preview ? "退出演示" : "紧急退出（暂停 15 分钟）…",
                                     target: self, action: #selector(emergencyExit))
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
    }

    private func closePanels() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        sound?.stop()
        fallbackSound?.stop()
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
        tick()
    }

    @objc private func emergencyExit() {
        guard !dialogOpen else { return }
        if preview { NSApp.terminate(nil); return }
        let alert = makeAlert(title: "暂停 15 分钟并退出？",
                              text: "本次不会记作已打卡。安装后会在 15 分钟到期后的约 1 分钟内重新提醒。\n永久停止请运行卸载脚本。")
        alert.addButton(withTitle: "继续提醒")
        alert.addButton(withTitle: "暂停并退出")
        dialogOpen = true
        let result = alert.runModal()
        dialogOpen = false
        guard result == .alertSecondButtonReturn else { return }
        do {
            let store = try self.store ?? StateStore(directory: directory)
            try store.pause(until: Date().addingTimeInterval(15 * 60), now: Date())
        } catch {
            showAlert(title: "暂停时间未保存", text: "\(error.localizedDescription)\n程序仍会退出；后台服务可能在 1 分钟内再次启动。可运行卸载脚本永久停止。")
        }
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
        process.arguments = times.arguments + ["--preview"]
        do { try process.run() } catch { showAlert(title: "无法启动演示", text: error.localizedDescription) }
    }

    @objc private func openRecords() {
        NSWorkspace.shared.open(directory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        sound?.stop()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        for (center, token) in observers { center.removeObserver(token) }
        closePanels()
    }
}
