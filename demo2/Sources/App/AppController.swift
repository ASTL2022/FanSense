import Cocoa
@preconcurrency import UserNotifications

// MARK: - App Controller

@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    // MARK: - State

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var dataTimer: Timer?
    var sliderDebounce: Timer?
    var tickCount: Int = 0
    var isPanelVisible = false

    var helperOK = false
    var lastIsOnAC = true
    var lastBat: BatteryInfo? = nil
    var powerSamples: [Double] = []
    var lastNotifyTime: Date? = nil
    var bgSampleTimer: Timer? = nil

    var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64) = (0, 0, 0)
    var prevNetBytes: (rx: UInt64, tx: UInt64, time: Double) = (0, 0, 0)

    var fanIsManual = false
    var iconFrames: [NSImage] = []
    var iconFrameIndex = 0
    var iconRotationTimer: Timer?
    var iconBaseImage: NSImage?

    var panel: NSPopover?
    var panelFirstShow = true
    var smoothCPUTemp: Double = 0; var smoothGPUTemp: Double = 0; var smoothBatteryTemp: Double = 0
    var smoothCPU: Double = 0; var smoothGPU: Double = 0; var smoothMem: Double = 0
    var smoothPowerW: Double = 0; var smoothNetRx: Double = 0; var smoothNetTx: Double = 0
    var clickMonitor: Any?

    // MARK: - Card views

    let tempCard    = TemperatureCard(frame: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: TemperatureCard.height()))
    let usageCard   = UsageCard(frame:       NSRect(x: 0, y: 0, width: Layout.panelWidth, height: UsageCard.height(count: 3)))
    let netCard     = NetworkCard(frame:     NSRect(x: 0, y: 0, width: Layout.panelWidth, height: NetworkCard.h))
    let diskCard    = DiskCard(frame:        NSRect(x: 0, y: 0, width: Layout.panelWidth, height: DiskCard.h))
    let fanCard     = FanCard(frame:         NSRect(x: 0, y: 0, width: Layout.panelWidth, height: FanCard.h))
    let batteryCard = BatteryCard(frame:     NSRect(x: 0, y: 0, width: Layout.panelWidth, height: BatteryCard.h))
    let effCard     = EfficiencyCard(frame:  NSRect(x: 0, y: 0, width: Layout.panelWidth, height: EfficiencyCard.h))

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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupIcon()
        buildPanel()
        checkHelper()
        refresh(slow: true)
        bgSampleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bgSample() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard helperOK else { return }
        runHelper(["auto"])
    }

    // MARK: - Panel show/hide

    @objc func togglePanel() {
        guard let p = panel else { return }
        if p.isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let p = panel, let btn = statusItem.button else { return }
        isPanelVisible = true
        if panelFirstShow { panelFirstShow = false }
        if dataTimer == nil {
            dataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.tickCount += 1
                    self.refresh(slow: self.tickCount % 30 == 0)
                }
            }
        }
        bgSampleTimer?.invalidate(); bgSampleTimer = nil
        refresh(slow: true)
        p.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)

        if let popoverWindow = p.contentViewController?.view.window {
            popoverWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hidePanel() }
        }
    }

    func hidePanel() {
        panel?.close()
        isPanelVisible = false
        dataTimer?.invalidate(); dataTimer = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if bgSampleTimer == nil {
            bgSampleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.bgSample() }
            }
        }
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
        btn.target = self
        btn.action = #selector(togglePanel)
        btn.sendAction(on: [.leftMouseDown, .rightMouseDown])

        let sz = sym.size
        iconFrames = (0..<30).map { i in
            let angle = CGFloat(i) * 2.0 * .pi / 30.0
            let img = NSImage(size: sz, flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.rotate(by: -angle)
                sym.draw(in: NSRect(x: -sz.width / 2, y: -sz.height / 2, width: sz.width, height: sz.height),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
                return true
            }
            img.isTemplate = true
            _ = img.tiffRepresentation
            return img
        }
    }

    func updateIconRotation() {
        guard let btn = statusItem.button, !iconFrames.isEmpty else { return }
        if fanIsManual {
            guard iconRotationTimer == nil else { return }
            iconRotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.iconFrameIndex = (self.iconFrameIndex + 1) % self.iconFrames.count
                    self.statusItem.button?.image = self.iconFrames[self.iconFrameIndex]
                }
            }
        } else {
            guard let timer = iconRotationTimer else { return }
            timer.invalidate(); iconRotationTimer = nil; iconFrameIndex = 0
            btn.image = iconBaseImage
        }
    }

    // MARK: - Panel

    func buildPanel() {
        tempCard.entries = [
            .init(label: "CPU", value: 0, warnAt: 60, critAt: 95),
            .init(label: "GPU", value: 0, warnAt: 60, critAt: 95),
            .init(label: "电池", value: 0, warnAt: 35, critAt: 45, maxTemp: 60),
        ]
        usageCard.entries = [
            .init(label: "CPU", valueStr: "--", percent: 0, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
            .init(label: "GPU", valueStr: "--", percent: 0, color: .systemGreen, warnAt: 0.70, critAt: 0.90),
            .init(label: "内存", valueStr: "--", percent: 0, color: .systemBlue, warnAt: 0.60, critAt: 0.90),
        ]
        netCard.cols = [
            .init(label: "下载", valueStr: "--", color: .systemTeal),
            .init(label: "上传", valueStr: "--", color: .systemTeal),
        ]
        diskCard.entries = [
            .init(label: "已用", valueStr: "--", percent: 0, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
            .init(label: "可用", valueStr: "--", percent: -1, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
        ]

        fanCard.onSliderChange = { [weak self] rpm in
            guard let self else { return }
            self.sliderDebounce?.invalidate()
            self.sliderDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.helperOK else { return }
                    if rpm <= self.fanCard.minRPM + 1 {
                        runHelper(["auto"]); self.fanCard.pendingChange = false
                    } else {
                        runHelper(["set", String(Int(rpm))])
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            self.fanCard.pendingChange = false
                        }
                    }
                    self.refresh()
                }
            }
        }

        let contentView = makeContentView()
        let totalH = contentView.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let panelH = min(totalH, maxH)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelH))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false; scroll.contentView.backgroundColor = .clear
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.clear.cgColor
        scroll.documentView = contentView

        let container = NSView(frame: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelH))
        container.addSubview(scroll)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = container
        popover.contentSize = NSSize(width: Layout.panelWidth, height: panelH)
        panel = popover

        addPanelBackdrop(to: container)
    }

    private func addPanelBackdrop(to container: NSView) {
        container.wantsLayer = true
        guard let filterClass = NSClassFromString("CAFilter"),
              let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return }
        let backdrop = backdropClass.init()
        var filters: [AnyObject] = []
        if let blur = makeFilter(cls: filterClass, type: "gaussianBlur") {
            blur.setValue(30.0, forKey: "inputRadius")
            blur.setValue("normalizedEdges", forKey: "inputNormalizeEdgesMode")
            blur.setValue(true, forKey: "inputNormalizeEdgesTransparent")
            filters.append(blur)
        }
        if let face = makeFilter(cls: filterClass, type: "glassFace") {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
                      || NSApp.effectiveAppearance.name == .vibrantDark
            face.setValue(isDark ? 0.10 : 0.12, forKey: "inputFaceOpacity")
            face.setValue(1.0, forKey: "inputFaceColorMatrixSaturation")
            face.setValue(1.0, forKey: "inputFaceColorMatrixWhite")
            face.setValue(0.0, forKey: "inputFaceColorMatrixBlack")
            filters.append(face)
        }
        backdrop.backgroundFilters = filters
        backdrop.frame = container.bounds
        backdrop.zPosition = -1
        container.layer?.addSublayer(backdrop)
    }

    private func makeFilter(cls: AnyClass, type: String) -> NSObject? {
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel) else { return nil }
        typealias F = @convention(c) (AnyClass, Selector, AnyObject) -> AnyObject
        let m = class_getClassMethod(cls, sel)!
        let imp = method_getImplementation(m)
        return unsafeBitCast(imp, to: F.self)(cls, sel, type as AnyObject) as? NSObject
    }

    func makeContentView() -> NSView {
        let hPad: CGFloat = 8, colGap: CGFloat = 8, btnH: CGFloat = 40
        let colW = (Layout.panelWidth - hPad * 2 - colGap) / 2

        let leftGroups:  [[NSView]] = [[batteryCard], [effCard], [fanCard]]
        let rightGroups: [[NSView]] = [[tempCard], [usageCard], [netCard], [diskCard]]

        func makeCard(_ views: [NSView], width: CGFloat) -> NSView {
            let vPad: CGFloat = 8
            var cardH: CGFloat = vPad
            for v in views { cardH += v.frame.height }
            cardH += vPad

            let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))
            var vy = vPad
            for v in views.reversed() {
                v.frame = NSRect(x: 0, y: vy, width: width, height: v.frame.height)
                content.addSubview(v)
                vy += v.frame.height
            }

            let card = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))
            card.wantsLayer = true
            card.layer?.cornerRadius = Layout.cardRadius
            card.layer?.masksToBounds = true
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
                      || NSApp.effectiveAppearance.name == .vibrantDark
            card.layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : NSColor.white.withAlphaComponent(0.45).cgColor
            card.addSubview(content)
            return card
        }

        func buildColumn(_ groups: [[NSView]], width: CGFloat) -> ([NSView], CGFloat) {
            var cards: [NSView] = []; var totalH: CGFloat = Layout.cardGap
            for group in groups {
                let card = makeCard(group, width: width)
                cards.append(card); totalH += card.frame.height + Layout.cardGap
            }
            return (cards, totalH)
        }

        let (leftCards, leftH)   = buildColumn(leftGroups, width: colW)
        let (rightCards, rightH) = buildColumn(rightGroups, width: colW)
        let contentH = max(leftH, rightH) + btnH + Layout.cardGap

        let container = NSView(frame: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: contentH))

        let leftX = hPad
        var ly = contentH - Layout.cardGap
        for card in leftCards {
            ly -= card.frame.height
            card.frame.origin = NSPoint(x: leftX, y: ly)
            container.addSubview(card)
            ly -= Layout.cardGap
        }

        let rightX = hPad + colW + colGap
        var ry = contentH - Layout.cardGap
        for card in rightCards {
            ry -= card.frame.height
            card.frame.origin = NSPoint(x: rightX, y: ry)
            container.addSubview(card)
            ry -= Layout.cardGap
        }

        let btnY = Layout.cardGap
        autoBtn.frame = NSRect(x: hPad, y: btnY + 7, width: 120, height: 26)
        quitBtn.frame = NSRect(x: Layout.panelWidth - hPad - 70, y: btnY + 7, width: 70, height: 26)
        container.addSubview(autoBtn)
        container.addSubview(quitBtn)

        return container
    }

    // MARK: - Actions

    @objc func setAuto() { guard helperOK else { return }; runHelper(["auto"]); refresh() }
    @objc func quit() { if helperOK { runHelper(["auto"]) }; NSApp.terminate(nil) }

    func checkHelper() {
        helperOK = FileManager.default.isExecutableFile(atPath: HELPER_PATH)
    }

    // MARK: - Background Sampling

    func bgSample() {
        guard helperOK else { return }
        Task.detached { [weak self] in
            let out = runHelper(["sensors"]); let s = parseSensors(out)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let w = s.pstr > 0 ? s.pstr : 0
                self.powerSamples.append(w)
                if self.powerSamples.count > 5 { self.powerSamples.removeFirst() }
                let avg = self.powerSamples.isEmpty ? 0.0 : self.powerSamples.reduce(0, +) / Double(self.powerSamples.count)
                self.effCard.avgWatts = avg; self.effCard.timeToEmpty = self.lastBat?.timeToEmpty ?? -1
                self.effCard.isOnBattery = !self.lastIsOnAC
                self.checkPowerAlert()
            }
        }
    }

    func checkPowerAlert() {
        guard !lastIsOnAC, powerSamples.count == 5 else { return }
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
                content.body = String(format: "均值 %.0fW · 剩余续航约 %d 小时 %d 分\n建议降低负载或连接电源", avgW, h, m)
                content.sound = .default
                let req = UNNotificationRequest(identifier: "power_alert", content: content, trigger: nil)
                center.add(req, withCompletionHandler: nil)
            }
        }
    }

    // MARK: - Refresh

    func ema(_ new: Double, prev: inout Double, alpha: Double = 0.35) -> Double {
        prev = prev * (1 - alpha) + new * alpha
        return prev
    }

    func refresh(slow: Bool = false) {
        guard helperOK else { return }

        let cpuInfo = readCPU(&prevCPUTicks)
        let netInfo = readNetwork(&prevNetBytes)

        Task.detached { [weak self, cpuInfo, netInfo] in
            guard let self else { return }
            let memInfo = readMemory()
            let isOpen = await MainActor.run(body: { self.isPanelVisible })

            let output  = isOpen ? runHelper(["all"]) : ""
            let parts   = output.components(separatedBy: "---\n")
            let fans    = isOpen ? parseFans(parts.first ?? "") : []
            let sensors = isOpen ? parseSensors(parts.count > 1 ? parts[1] : "") : SensorData()
            let disk    = (isOpen && slow) ? readDisk() : nil
            let bat     = isOpen ? readBattery() : nil

            await MainActor.run { [weak self] in
                guard let self else { return }

                let isOnAC     = bat?.isOnAC     ?? self.lastIsOnAC
                let isCharging = bat?.isCharging ?? false
                let batFull    = (bat?.percent ?? self.lastBat?.percent ?? 0) >= 1.0
                let powerMode  = isOnAC ? ((isCharging || !batFull) ? 1 : 2) : 0
                let systemPowerW = isOnAC ? (sensors.pdtr > 0 ? sensors.pdtr : sensors.pstr) : sensors.pstr
                let sPower = ema(systemPowerW, prev: &self.smoothPowerW, alpha: 0.4)

                if self.isPanelVisible {
                    self.batteryCard.powerMode = powerMode
                    self.batteryCard.pushSample(watts: sPower)
                    if self.tickCount % 60 == 0 {
                        let w = sPower > 0 ? sPower : 0
                        self.powerSamples.append(w)
                        if self.powerSamples.count > 5 { self.powerSamples.removeFirst() }
                        let avg = self.powerSamples.isEmpty ? 0.0 : self.powerSamples.reduce(0, +) / Double(self.powerSamples.count)
                        self.effCard.avgWatts = avg
                        self.effCard.timeToEmpty = self.lastBat?.timeToEmpty ?? -1
                        self.effCard.isOnBattery = !self.lastIsOnAC
                        self.checkPowerAlert()
                    }
                }

                guard self.isPanelVisible else { return }

                // Fan
                if let f = fans.first {
                    let manual = fans.contains { $0.mode == 1 }
                    let lo = fans.map(\.min).min() ?? 1500
                    let hi = fans.map(\.max).max() ?? 4700
                    self.fanIsManual = manual
                    self.fanCard.update(cur: f.cur, min: lo, max: hi, target: f.target, manual: manual)
                }
                self.updateIconRotation()

                // Temperature
                let sCT = ema(sensors.cpuTemp,     prev: &self.smoothCPUTemp)
                let sGT = ema(sensors.gpuTemp,     prev: &self.smoothGPUTemp)
                let sBT = ema(sensors.batteryTemp, prev: &self.smoothBatteryTemp)
                self.tempCard.entries = [
                    .init(label: "CPU", value: sCT, warnAt: 60, critAt: 95),
                    .init(label: "GPU", value: sGT, warnAt: 60, critAt: 95),
                    .init(label: "电池", value: sBT, warnAt: 35, critAt: 45, maxTemp: 60),
                ]

                // Usage
                let gpuUtil = readGPUUtil()
                let sCPU = ema(cpuInfo.percent, prev: &self.smoothCPU)
                let sGPU = gpuUtil >= 0 ? ema(gpuUtil, prev: &self.smoothGPU) : gpuUtil
                let sMem = ema(memInfo.percent, prev: &self.smoothMem)
                self.usageCard.entries = [
                    .init(label: "CPU",  valueStr: String(format: "%.0f%%", sCPU * 100),
                          percent: sCPU, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
                    .init(label: "GPU",  valueStr: gpuUtil >= 0 ? String(format: "%.0f%%", sGPU * 100) : "--",
                          percent: sGPU, color: .systemGreen, warnAt: 0.70, critAt: 0.90),
                    .init(label: "内存", valueStr: String(format: "%.0f%%", sMem * 100),
                          percent: sMem, color: .systemBlue, warnAt: 0.60, critAt: 0.90),
                ]

                // Network
                let sRx = ema(netInfo.rxBytesPerSec, prev: &self.smoothNetRx, alpha: 0.5)
                let sTx = ema(netInfo.txBytesPerSec, prev: &self.smoothNetTx, alpha: 0.5)
                self.netCard.cols = [
                    .init(label: "下载", valueStr: formatBytes(sRx), color: .systemTeal),
                    .init(label: "上传", valueStr: formatBytes(sTx), color: .systemTeal),
                ]

                // Disk
                if let d = disk {
                    let freeGB = d.totalGB - d.usedGB
                    self.diskCard.entries = [
                        .init(label: "已用", valueStr: String(format: "%.0f%%", d.percent * 100),
                              percent: d.percent, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                        .init(label: "可用", valueStr: String(format: "%.0fG", freeGB),
                              percent: -1, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                    ]
                }

                // Battery
                if let bat {
                    self.batteryCard.isHidden = !bat.hasBattery
                    self.lastIsOnAC = bat.isOnAC
                    if bat.hasBattery {
                        self.batteryCard.percent = bat.percent
                        self.lastBat = bat
                    }
                } else if let cached = self.lastBat {
                    self.batteryCard.isHidden = !cached.hasBattery
                }

                if let bat = self.lastBat {
                    let wattsStr = String(format: "%.1fW", sPower)
                    self.batteryCard.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                    self.batteryCard.powerMode = powerMode
                    self.effCard.isOnBattery = (powerMode == 0)

                    if powerMode == 1 {
                        self.batteryCard.timeLine = wattsStr
                    } else if powerMode == 0 {
                        let tte = bat.timeToEmpty
                        self.batteryCard.timeLine = tte > 0
                            ? "剩余续航 \(tte / 60)小时\(tte % 60)分  ·  \(wattsStr)" : wattsStr
                    } else {
                        let tempStr = sensors.batteryTemp > 0
                            ? String(format: "  ·  %.1f°C", sensors.batteryTemp) : ""
                        self.batteryCard.timeLine = bat.healthPercent > 0
                            ? String(format: "健康 %.0f%%  ·  %d 次循环%@", bat.healthPercent * 100, bat.cycleCount, tempStr) : ""
                    }
                    self.batteryCard.display()
                    self.effCard.display()
                }
            }
        }
    }
}
