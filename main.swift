import Cocoa
@preconcurrency import UserNotifications

let W: CGFloat       = 560
let PAD: CGFloat     = 16
let IP: CGFloat      = 16
let GAP: CGFloat     = 10
let TR: CGFloat      = 2.5
let CR: CGFloat      = 1.25
let CARD_R: CGFloat  = 14
let PANEL_R: CGFloat = 18

@MainActor
final class AppController: NSObject, NSApplicationDelegate, @preconcurrency NSStatusItemExpandedInterfaceDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var dataTimer: Timer?
    var sliderDebounce: Timer?

    var avgRPM: Double = 0
    var fanIsManual: Bool = false
    var iconRotationActive = false
    var iconRotationTimer: Timer?
    var iconBaseImage: NSImage?
    var iconFrames: [NSImage] = []
    var iconFrameIndex: Int = 0

    var tickCount: Int = 0
    var isPanelVisible: Bool = false
    var glassViews: [NSView] = []

    var panel: NSPanel?
    var clickMonitor: Any?

    let headerView     = HeaderView(frame:     NSRect(x: 0, y: 0, width: W, height: HeaderView.h))
    let tempBarView    = TempBarView(frame:    NSRect(x: 0, y: 0, width: W,
                                               height: TempBarView.height(count: 3)))
    let batteryBarView = BatteryBarView(frame: NSRect(x: 0, y: 0, width: W,
                                               height: BatteryBarView.h))
    let efficiencyView = EfficiencyView(frame: NSRect(x: 0, y: 0, width: W,
                                               height: EfficiencyView.viewH))
    let fanSliderView  = FanSliderView(frame:  NSRect(x: 0, y: 0, width: W, height: FanSliderView.h))
    let metricBarView  = MetricBarView(frame: NSRect(x: 0, y: 0, width: W,
                                               height: MetricBarView.height(count: 3)))
    let netBarView     = NetBarView(frame:      NSRect(x: 0, y: 0, width: W,
                                               height: NetBarView.height()))
    let diskBarView    = MetricBarView(frame: NSRect(x: 0, y: 0, width: W,
                                               height: MetricBarView.height(count: 2)))

    lazy var autoBtn: NSButton = {
        let b = NSButton(title: "恢复自动温控", target: self, action: #selector(setAuto))
        b.bezelStyle = .rounded; b.font = .systemFont(ofSize: 12)
        return b
    }()
    lazy var quitBtn: NSButton = {
        let b = NSButton(title: "退出", target: self, action: #selector(quit))
        b.bezelStyle = .rounded; b.font = .systemFont(ofSize: 12)
        return b
    }()

    var helperOK = false
    var lastIsOnAC: Bool = true
    var lastBat: BatteryInfo? = nil
    var powerSamples: [Double] = []
    var lastNotifyTime: Date? = nil
    var bgSampleTimer: Timer? = nil

    var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64) = (0, 0, 0)
    var prevNetBytes: (rx: UInt64, tx: UInt64, time: Double) = (0, 0, 0)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupIcon()
        buildPanel()
        checkHelper()
        refresh(slow: true)
        dataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickCount += 1
                self.refresh(slow: self.tickCount % 30 == 0)
            }
        }
        bgSampleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bgSample() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemGlassTintChanged),
            name: NSNotification.Name("AppleGlobalDomainPreferencesChanged"),
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard helperOK else { return }
        runHelper(["auto"])
    }

    // MARK: - NSStatusItemExpandedInterfaceDelegate

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        guard let p = panel, let btn = statusItem.button,
              let screen = btn.window?.screen ?? NSScreen.main else { return }

        let btnRect = btn.window!.convertToScreen(btn.frame)
        let x = min(btnRect.midX - W / 2,
                    screen.visibleFrame.maxX - W)
        let y = btnRect.minY - p.frame.height - 2

        p.setFrameOrigin(NSPoint(x: max(x, screen.visibleFrame.minX), y: y))
        p.makeKeyAndOrderFront(nil)

        isPanelVisible = true
        applySystemGlassTintToAll(glassViews)
        refresh(slow: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.statusItem.expandedInterfaceSession?.cancel()
            }
        }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        panel?.orderOut(nil)
        isPanelVisible = false
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    @objc func systemGlassTintChanged() {
        applySystemGlassTintToAll(glassViews)
    }

    // MARK: - Icon

    func setupIcon() {
        guard let btn = statusItem.button else { return }

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let sym = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?
                      .withSymbolConfiguration(cfg)
               ?? NSImage(systemSymbolName: "fan", accessibilityDescription: nil)?
                      .withSymbolConfiguration(cfg)
        guard let sym else { return }
        sym.isTemplate = true
        iconBaseImage = sym
        btn.image = sym
        loadIconFrames()

        statusItem.expandedInterfaceDelegate = self
    }

    func loadIconFrames() {
        guard let base = iconBaseImage else { return }
        let sz = base.size
        iconFrames = (0..<30).map { i in
            let angle = CGFloat(i) * 2.0 * .pi / 30.0
            let img = NSImage(size: sz, flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.rotate(by: -angle)
                base.draw(in: NSRect(x: -sz.width / 2, y: -sz.height / 2, width: sz.width, height: sz.height),
                          from: .zero, operation: .sourceOver, fraction: 1.0)
                return true
            }
            img.isTemplate = true
            _ = img.tiffRepresentation
            return img
        }
    }

    // MARK: - Panel

    func buildPanel() {
        tempBarView.sectionTitle = "温度"
        tempBarView.entries = [
            .init(label: "CPU",  value: 0, warnAt: 60, critAt: 95),
            .init(label: "GPU",  value: 0, warnAt: 60, critAt: 95),
            .init(label: "电池", value: 0, warnAt: 35, critAt: 45, maxTemp: 60),
        ]
        metricBarView.sectionTitle = "占用"
        metricBarView.entries = [
            .init(label: "CPU",  valueStr: "--", percent: 0, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
            .init(label: "GPU",  valueStr: "--", percent: 0, color: .systemGreen,  warnAt: 0.70, critAt: 0.90),
            .init(label: "内存", valueStr: "--", percent: 0, color: .systemBlue,   warnAt: 0.60, critAt: 0.90),
        ]
        netBarView.sectionTitle = "网络"
        netBarView.cols = [
            .init(label: "下载", valueStr: "--", color: .systemTeal),
            .init(label: "上传", valueStr: "--", color: .systemTeal),
        ]
        diskBarView.sectionTitle = "磁盘"
        diskBarView.entries = [
            .init(label: "已用", valueStr: "--", percent: 0,  color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
            .init(label: "可用", valueStr: "--", percent: -1, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
        ]
        fanSliderView.onSliderChange = { [weak self] rpm in
            guard let self else { return }
            self.sliderDebounce?.invalidate()
            self.sliderDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.helperOK else { return }
                    if rpm <= self.fanSliderView.minRPM + 1 {
                        runHelper(["auto"])
                        self.fanSliderView.pendingChange = false
                    } else {
                        runHelper(["set", String(Int(rpm))])
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            self.fanSliderView.pendingChange = false
                        }
                    }
                    self.refresh()
                }
            }
        }

        glassViews = []

        let contentView = makeContentView()
        let totalH = contentView.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let panelH = min(totalH, maxH)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: panelH))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false
        scroll.contentView.backgroundColor = .clear
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.clear.cgColor
        scroll.documentView = contentView

        let container = makeGlassContainer()
        container.frame = NSRect(x: 0, y: 0, width: W, height: panelH)
        container.autoresizingMask = [.width, .height]
        container.addSubview(scroll)

        let p = TransparentPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = container
        self.panel = p
    }

    private func makeContentView() -> NSView {
        let hPad:  CGFloat = 8
        let colGap: CGFloat = 8
        let btnH:  CGFloat = 40
        let colW = (W - hPad * 2 - colGap) / 2

        let leftGroups:  [[NSView]] = [
            [batteryBarView],
            [efficiencyView],
            [fanSliderView],
        ]
        let rightGroups: [[NSView]] = [
            [tempBarView],
            [metricBarView],
            [netBarView],
            [diskBarView],
        ]

        func makeCard(_ views: [NSView], width: CGFloat) -> NSView {
            let vPad: CGFloat = 8
            var cardH: CGFloat = vPad
            for v in views { cardH += v.frame.height }
            cardH += vPad

            let cardContent = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))

            var vy = vPad
            for v in views.reversed() {
                v.frame = NSRect(x: 0, y: vy, width: width, height: v.frame.height)
                cardContent.addSubview(v)
                vy += v.frame.height
            }

            let cardGlass = makeGlass(cornerRadius: CARD_R, interactive: true)
            cardGlass.frame = NSRect(x: 0, y: 0, width: width, height: cardH)
            setGlassContentView(cardGlass, cardContent)
            glassViews.append(cardGlass)
            return cardGlass
        }

        func buildColumn(_ groups: [[NSView]], width: CGFloat) -> ([NSView], CGFloat) {
            var cards: [NSView] = []
            var totalH: CGFloat = GAP
            for group in groups {
                let card = makeCard(group, width: width)
                cards.append(card)
                totalH += card.frame.height + GAP
            }
            return (cards, totalH)
        }

        let (leftCards,  leftH)  = buildColumn(leftGroups,  width: colW)
        let (rightCards, rightH) = buildColumn(rightGroups, width: colW)
        let contentH = max(leftH, rightH) + btnH + GAP

        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: contentH))

        let leftX = hPad
        var ly = contentH - GAP
        for card in leftCards {
            ly -= card.frame.height
            card.frame.origin = NSPoint(x: leftX, y: ly)
            container.addSubview(card)
            ly -= GAP
        }

        let rightX = hPad + colW + colGap
        var ry = contentH - GAP
        for card in rightCards {
            ry -= card.frame.height
            card.frame.origin = NSPoint(x: rightX, y: ry)
            container.addSubview(card)
            ry -= GAP
        }

        autoBtn.bezelStyle = .rounded
        autoBtn.font = .systemFont(ofSize: 12)
        quitBtn.bezelStyle = .rounded
        quitBtn.font = .systemFont(ofSize: 12)

        let btnY = GAP
        autoBtn.frame = NSRect(x: hPad, y: btnY + 7, width: 120, height: 26)
        quitBtn.frame = NSRect(x: W - hPad - 70, y: btnY + 7, width: 70, height: 26)
        container.addSubview(autoBtn)
        container.addSubview(quitBtn)

        return container
    }

    func relayoutPanel() {
        guard let p = panel,
              let container = p.contentView,
              let scroll = container.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
        else { return }
        let contentView = makeContentView()
        scroll.documentView = contentView
        let totalH = contentView.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let panelH = min(totalH, maxH)
        var f = p.frame; f.size.height = panelH
        let topY = f.origin.y + p.frame.height
        f.origin.y = topY - panelH
        p.setFrame(f, display: true, animate: false)
        container.frame = NSRect(x: 0, y: 0, width: W, height: panelH)
        scroll.frame = NSRect(x: 0, y: 0, width: W, height: panelH)
        applySystemGlassTintToAll(glassViews)
    }

    // MARK: - Actions

    @objc func setAuto() {
        guard helperOK else { return }
        runHelper(["auto"])
        refresh()
    }

    @objc func quit() {
        if helperOK { runHelper(["auto"]) }
        NSApp.terminate(nil)
    }

    func checkHelper() {
        helperOK = FileManager.default.isExecutableFile(atPath: HELPER)
    }

    func requireHelper() -> Bool {
        if helperOK { return true }
        let a = NSAlert()
        a.messageText = "helper 未安装"
        a.informativeText = "请先运行安装脚本（需要 sudo）安装 \(HELPER)。"
        a.runModal()
        return false
    }

    // MARK: - Background Sampling & Power Alerts

    func bgSample() {
        guard helperOK else { return }
        Task.detached { [weak self] in
            let out = runHelper(["sensors"])
            let s   = parseSensors(out)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let w = s.pstr > 0 ? s.pstr : 0
                self.powerSamples.append(w)
                if self.powerSamples.count > 5 { self.powerSamples.removeFirst() }
                let avg = self.powerSamples.isEmpty ? 0.0
                    : self.powerSamples.reduce(0, +) / Double(self.powerSamples.count)
                self.efficiencyView.avgWatts    = avg
                self.efficiencyView.timeToEmpty = self.lastBat?.timeToEmpty ?? -1
                self.efficiencyView.isOnBattery = !self.lastIsOnAC
                self.efficiencyView.display()
                self.checkPowerAlert()
            }
        }
    }

    func checkPowerAlert() {
        guard !lastIsOnAC else { return }
        guard powerSamples.count == 5 else { return }
        let avg = powerSamples.reduce(0, +) / 5.0
        guard avg >= 15 else { return }
        let tte = lastBat?.timeToEmpty ?? -1
        guard tte > 0 && tte < 180 else { return }
        if let last = lastNotifyTime, Date().timeIntervalSince(last) < 1800 { return }
        lastNotifyTime = Date()
        sendPowerAlert(avgW: avg, minutesLeft: tte)
    }

    func sendPowerAlert(avgW: Double, minutesLeft: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = "高功耗提醒"
                let h = minutesLeft / 60, m = minutesLeft % 60
                content.body = String(
                    format: "均值 %.0fW · 剩余续航约 %d 小时 %d 分\n建议降低负载或连接电源",
                    avgW, h, m)
                content.sound = .default
                let req = UNNotificationRequest(identifier: "power_alert", content: content, trigger: nil)
                center.add(req, withCompletionHandler: nil)
            }
        }
    }

    // MARK: - Data Refresh

    func refresh(slow: Bool = false) {
        guard helperOK else { return }

        let cpuInfo = readCPU(prevTicks: &prevCPUTicks)
        let netInfo = readNetwork(prevBytes: &prevNetBytes)

        Task.detached { [weak self, cpuInfo, netInfo] in
            guard let self else { return }

            let memInfo = readMemory()

            let isOpen = await MainActor.run(body: { self.isPanelVisible })
            let output   = isOpen ? runHelper(["all"]) : ""
            let parts    = output.components(separatedBy: "---\n")
            let fans     = isOpen ? parseFans(parts.first ?? "") : []
            let sensors  = isOpen ? parseSensors(parts.count > 1 ? parts[1] : "") : SensorData()
            let diskInfo = (isOpen && slow) ? readDisk()         : nil
            let bat      = isOpen           ? readBatteryPS()  : nil
            let hdr      = (isOpen && slow) ? readSystemHeader() : nil

            await MainActor.run { [weak self] in
                guard let self else { return }

                let isOnAC     = bat?.isOnAC     ?? self.lastIsOnAC
                let isCharging = bat?.isCharging ?? false
                let batFull    = (bat?.percent ?? self.lastBat?.percent ?? 0) >= 1.0
                let powerMode: Int = isOnAC ? ((isCharging || !batFull) ? 1 : 2) : 0

                let systemPowerW: Double = isOnAC
                    ? (sensors.pdtr > 0 ? sensors.pdtr : sensors.pstr)
                    : sensors.pstr

                if self.isPanelVisible {
                    self.batteryBarView.powerMode = powerMode
                    self.batteryBarView.pushSample(watts: systemPowerW)
                }

                guard self.isPanelVisible else { return }

                if let hdr {
                    self.headerView.modelName  = hdr.modelName
                    self.headerView.uptimeLine = hdr.uptimeStr
                    self.headerView.display()
                }

                self.avgRPM = fans.isEmpty ? 0 : fans.map(\.cur).reduce(0, +) / Double(fans.count)
                if let f = fans.first {
                    let manual = fans.contains { $0.mode == 1 }
                    let lo = fans.map(\.min).min() ?? 1500
                    let hi = fans.map(\.max).max() ?? 4700
                    self.fanIsManual = manual
                    self.fanSliderView.update(cur: f.cur, min: lo, max: hi, target: f.target, manual: manual)
                }
                self.updateIconRotation()

                self.tempBarView.entries = [
                    .init(label: "CPU",  value: sensors.cpuTemp,     warnAt: 60, critAt: 95),
                    .init(label: "GPU",  value: sensors.gpuTemp,     warnAt: 60, critAt: 95),
                    .init(label: "电池", value: sensors.batteryTemp,  warnAt: 35, critAt: 45, maxTemp: 60),
                ]
                self.tempBarView.display()

                let gpuUtil = readGPUUtilization()

                self.metricBarView.entries = [
                    .init(label: "CPU",
                          valueStr: String(format: "%.0f%%", cpuInfo.percent * 100),
                          percent: cpuInfo.percent, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
                    .init(label: "GPU",
                          valueStr: gpuUtil >= 0 ? String(format: "%.0f%%", gpuUtil * 100) : "--",
                          percent: gpuUtil, color: .systemGreen, warnAt: 0.70, critAt: 0.90),
                    .init(label: "内存",
                          valueStr: String(format: "%.0f%%", memInfo.percent * 100),
                          percent: memInfo.percent, color: .systemBlue, warnAt: 0.60, critAt: 0.90),
                ]
                self.metricBarView.display()

                self.netBarView.cols = [
                    .init(label: "下载", valueStr: formatBytes(netInfo.rxBytesPerSec), color: .systemTeal),
                    .init(label: "上传", valueStr: formatBytes(netInfo.txBytesPerSec), color: .systemTeal),
                ]
                self.netBarView.display()

                if let d = diskInfo {
                    let freeGB = d.totalGB - d.usedGB
                    self.diskBarView.entries = [
                        .init(label: "已用", valueStr: String(format: "%.0f%%", d.percent * 100),
                              percent: d.percent, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                        .init(label: "可用", valueStr: String(format: "%.0fG", freeGB),
                              percent: -1, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                    ]
                    self.diskBarView.display()
                }

                if let bat {
                    self.batteryBarView.isHidden = !bat.hasBattery
                    self.lastIsOnAC = bat.isOnAC
                    if bat.hasBattery {
                        self.batteryBarView.percent = bat.percent
                        self.lastBat = bat
                    }
                } else if let cached = self.lastBat {
                    self.batteryBarView.isHidden = !cached.hasBattery
                }

                if let bat = self.lastBat {
                    let wattsStr = String(format: "%.1fW", systemPowerW)
                    self.batteryBarView.isLowPower    = ProcessInfo.processInfo.isLowPowerModeEnabled
                    self.efficiencyView.isOnBattery   = (powerMode == 0)
                    if powerMode == 1 {
                        self.batteryBarView.timeLine   = wattsStr
                    } else if powerMode == 0 {
                        let tte = bat.timeToEmpty
                        self.batteryBarView.timeLine   = tte > 0 ? "剩余续航 \(tte / 60)小时\(tte % 60)分  ·  \(wattsStr)" : wattsStr
                    } else {
                        let tempStr = sensors.batteryTemp > 0
                            ? String(format: "  ·  %.1f°C", sensors.batteryTemp) : ""
                        self.batteryBarView.timeLine = bat.healthPercent > 0
                            ? String(format: "健康 %.0f%%  ·  %d 次循环%@",
                                     bat.healthPercent * 100, bat.cycleCount, tempStr) : ""
                    }
                    self.batteryBarView.display()
                }
            }
        }
    }

    // MARK: - Icon rotation

    func updateIconRotation() {
        guard let btn = statusItem.button, !iconFrames.isEmpty else { return }

        if fanIsManual {
            guard !iconRotationActive else { return }
            iconRotationActive = true
            iconRotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.iconFrameIndex = (self.iconFrameIndex + 1) % self.iconFrames.count
                    self.statusItem.button?.image = self.iconFrames[self.iconFrameIndex]
                }
            }
        } else {
            guard iconRotationActive else { return }
            iconRotationActive = false
            iconRotationTimer?.invalidate()
            iconRotationTimer = nil
            iconFrameIndex = 0
            btn.image = iconBaseImage
        }
    }
}

// MARK: - Entry

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.run()
}
