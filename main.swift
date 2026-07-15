import Cocoa
import SwiftUI
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
final class IconModel: ObservableObject {
    @Published var spinning = false
    @Published var hot = false
}

struct StatusIconView: View {
    @ObservedObject var model: IconModel
    var body: some View {
        Image(systemName: model.hot ? "flame.fill" : "fan.fill")
            .font(.system(size: 13, weight: .medium))
            .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: model.spinning && !model.hot)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(model.hot ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var dataTimer: Timer?
    var sliderDebounce: Timer?
    var bgSampleTimer: Timer?
    var setGeneration = 0

    var avgRPM: Double = 0
    var fanIsManual: Bool = false
    let iconModel = IconModel()

    var tickCount: Int = 0
    var isPanelVisible: Bool = false

    var panel: NSPanel?
    var clickMonitor: Any?

    let headerView     = HeaderView(frame: NSRect(x: 0, y: 0, width: W, height: HeaderView.h))
    let tempBarView    = TempBarView(frame: NSRect(x: 0, y: 0, width: W, height: TempBarView.height(count: 3)))
    let batteryBarView = BatteryBarView(frame: NSRect(x: 0, y: 0, width: W, height: BatteryBarView.h))
    let efficiencyView = EfficiencyView(frame: NSRect(x: 0, y: 0, width: W, height: EfficiencyView.viewH))
    let fanView        = FanView(frame: NSRect(x: 0, y: 0, width: W, height: FanView.h))
    let metricBarView  = MetricBarView(frame: NSRect(x: 0, y: 0, width: W, height: MetricBarView.height(count: 3)))
    let netBarView     = NetBarView(frame: NSRect(x: 0, y: 0, width: W, height: NetBarView.height()))
    let diskBarView    = MetricBarView(frame: NSRect(x: 0, y: 0, width: W, height: MetricBarView.height(count: 2)))

    var helperOK = false
    var smartInfo: SmartInfo?
    var lastIsOnAC: Bool = true
    var lastBat: BatteryInfo? = nil
    var powerSamples: [Double] = []
    var lastNotifyTime: Date? = nil

    var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64) = (0, 0, 0)
    var prevNetBytes: (rx: UInt64, tx: UInt64, time: Double) = (0, 0, 0)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupIcon()

        let contentView = makeContentView()
        let totalH = contentView.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let panelH = min(totalH, maxH)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: panelH))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = contentView

        let panelView = makeGlassPanel(cornerRadius: PANEL_R)
        panelView.frame = NSRect(x: 0, y: 0, width: W, height: panelH)
        panelView.addSubview(scroll)
        scroll.frame = panelView.bounds
        scroll.autoresizingMask = [.width, .height]

        initViewData()

        let p = TransparentPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = false
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = panelView
        self.panel = p

        checkHelper()
        ensureHelper()
        readSmartOnce()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard helperOK else { return }
        runHelper(["auto"])
    }

    // MARK: - Status Item

    func setupIcon() {
        guard let btn = statusItem.button else { return }
        let host = NSHostingView(rootView: StatusIconView(model: iconModel))
        host.frame = btn.bounds
        host.autoresizingMask = [.width, .height]
        btn.addSubview(host)
        btn.target = self
        btn.action = #selector(statusClicked)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceDelegate = self
        }
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuitMenu()
        } else if #unavailable(macOS 27.0) {
            togglePanel()
        }
    }

    func showQuitMenu() {
        guard let btn = statusItem.button else { return }
        let menu = NSMenu()
        let item = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        item.target = self
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.height + 4), in: btn)
    }

    // MARK: - Panel Show/Hide

    func showPanel() {
        guard let p = panel, let btn = statusItem.button,
              let screen = btn.window?.screen ?? NSScreen.main else { return }

        let btnRect = btn.window!.convertToScreen(btn.frame)
        let x = min(btnRect.midX - W / 2, screen.visibleFrame.maxX - W)
        let y = btnRect.minY - p.frame.height - 2

        p.setFrameOrigin(NSPoint(x: max(x, screen.visibleFrame.minX), y: y))
        p.makeKeyAndOrderFront(nil)

        isPanelVisible = true
        refresh(slow: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if #available(macOS 27.0, *) {
                    self.statusItem.expandedInterfaceSession?.cancel()
                } else {
                    self.hidePanel()
                }
            }
        }
    }

    func hidePanel() {
        panel?.orderOut(nil)
        isPanelVisible = false
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    @objc func togglePanel() {
        isPanelVisible ? hidePanel() : showPanel()
    }

    // MARK: - Views

    func initViewData() {
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
            .init(label: "健康", valueStr: "--", percent: 0,  color: .systemGreen,  warnAt: 2, critAt: 2),
        ]
        fanView.onSliderChange = { [weak self] rpm in
            guard let self else { return }
            self.sliderDebounce?.invalidate()
            self.sliderDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.helperOK else { self.fanView.pendingChange = false; return }
                    self.setGeneration += 1
                    let gen = self.setGeneration
                    if rpm <= self.fanView.minRPM + 1 {
                        runHelper(["auto"])
                        self.fanView.pendingChange = false
                        self.refresh()
                    } else {
                        let target = Int(rpm)
                        Task.detached { [weak self] in
                            // Verify the SMC write landed (mode=1); retry on transient failure.
                            var confirmed = false
                            for attempt in 0..<3 {
                                let fans = parseFans(runHelper(["set", String(target)]))
                                if fans.contains(where: { $0.mode == 1 }) { confirmed = true; break }
                                NSLog("FanSense: set %d rpm not confirmed (attempt %d)", target, attempt + 1)
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                            await MainActor.run { [weak self, confirmed] in
                                guard let self, gen == self.setGeneration else { return }
                                if !confirmed { NSLog("FanSense: set %d rpm failed after retries", target) }
                                self.fanView.pendingChange = false
                                self.refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    private func makeContentView() -> NSView {
        let hPad:  CGFloat = 8
        let colGap: CGFloat = 8
        let colW = (W - hPad * 2 - colGap) / 2

        let leftGroups:  [[NSView]] = [[batteryBarView], [efficiencyView], [fanView]]
        let rightGroups: [[NSView]] = [[tempBarView], [metricBarView], [netBarView], [diskBarView]]

        func makeCardView(_ views: [NSView], width: CGFloat) -> NSView {
            let vPad: CGFloat = 8
            var cardH: CGFloat = vPad
            for v in views { cardH += v.frame.height }
            cardH += vPad
            let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))
            var vy = vPad
            for v in views.reversed() {
                v.frame = NSRect(x: 0, y: vy, width: width, height: v.frame.height)
                box.addSubview(v)
                vy += v.frame.height
            }
            let card = makeCard(cornerRadius: CARD_R)
            card.frame = NSRect(x: 0, y: 0, width: width, height: cardH)
            embedInCard(card, box)
            return card
        }

        func buildCol(_ groups: [[NSView]], width: CGFloat) -> ([NSView], CGFloat) {
            var cards: [NSView] = []
            var h: CGFloat = GAP
            for g in groups {
                let c = makeCardView(g, width: width)
                cards.append(c)
                h += c.frame.height + GAP
            }
            return (cards, h)
        }

        let (leftCards,  leftH)  = buildCol(leftGroups,  width: colW)
        let (rightCards, rightH) = buildCol(rightGroups, width: colW)
        let contentH = max(leftH, rightH)

        let c = NSView(frame: NSRect(x: 0, y: 0, width: W, height: contentH))
        let lx = hPad; var ly = contentH - GAP
        for card in leftCards { ly -= card.frame.height; card.frame.origin = NSPoint(x: lx, y: ly); c.addSubview(card); ly -= GAP }
        let rx = hPad + colW + colGap; var ry = contentH - GAP
        for card in rightCards { ry -= card.frame.height; card.frame.origin = NSPoint(x: rx, y: ry); c.addSubview(card); ry -= GAP }
        return c
    }

    func relayoutPanel() {
        guard let p = panel, let panelView = p.contentView,
              let scroll = panelView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
        else { return }
        let cv = makeContentView()
        scroll.documentView = cv
        let totalH = cv.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let h = min(totalH, maxH)
        var f = p.frame; let top = f.origin.y + f.height
        f.size.height = h; f.origin.y = top - h
        p.setFrame(f, display: true, animate: false)
        panelView.frame = NSRect(x: 0, y: 0, width: W, height: h)
        scroll.frame = panelView.bounds
    }

    // MARK: - Actions

    @objc func quit() { if helperOK { runHelper(["auto"]) }; NSApp.terminate(nil) }
    func checkHelper() { helperOK = FileManager.default.isExecutableFile(atPath: HELPER) }

    static let helperVersion = "3"

    func ensureHelper() {
        let installed = FileManager.default.isExecutableFile(atPath: HELPER)
        if installed,
           runHelper(["version"]).trimmingCharacters(in: .whitespacesAndNewlines) == Self.helperVersion {
            helperOK = true
            return
        }
        guard let bundled = Bundle.main.path(forResource: "fanhelper", ofType: nil) else { return }

        let alert = NSAlert()
        alert.messageText = installed ? "需要更新风扇控制组件" : "需要安装风扇控制组件"
        alert.informativeText = "FanSense 通过 fanhelper（安装到 /usr/local/bin）读取传感器并控制风扇转速，安装需要管理员权限，仅需一次。"
        alert.addButton(withTitle: installed ? "更新" : "安装")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let cmd = "mkdir -p /usr/local/bin && cp \\\"\(bundled)\\\" \(HELPER) && xattr -c \(HELPER) 2>/dev/null; chown root:wheel \(HELPER) && chmod 4755 \(HELPER)"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        checkHelper()
    }

    func readSmartOnce() {
        guard helperOK else { return }
        Task.detached { [weak self] in
            let info = parseSmart(runHelper(["smart"]))
            await MainActor.run { [weak self] in self?.smartInfo = info }
        }
    }

    // MARK: - Background & Alerts

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
                self.efficiencyView.avgWatts = avg
                self.efficiencyView.timeToEmpty = self.lastBat?.timeToEmpty ?? -1
                self.efficiencyView.isOnBattery = !self.lastIsOnAC
                self.efficiencyView.display()
                self.updateIconHot(cpu: s.cpuTemp, gpu: s.gpuTemp)
                self.checkPowerAlert()
            }
        }
    }

    func checkPowerAlert() {
        guard !lastIsOnAC, powerSamples.count == 5 else { return }
        let avg = powerSamples.reduce(0, +) / 5.0
        guard avg >= 15 else { return }
        let tte = lastBat?.timeToEmpty ?? -1
        guard tte > 0, tte < 180 else { return }
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
                content.body = String(format: "均值 %.0fW · 剩余续航约 %d 小时 %d 分", avgW, h, m)
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "power_alert", content: content, trigger: nil))
            }
        }
    }

    // MARK: - Data Refresh

    func refresh(slow: Bool = false) {
        let cpuInfo = readCPU(prevTicks: &prevCPUTicks)
        let netInfo = readNetwork(prevBytes: &prevNetBytes)

        Task.detached { [weak self, cpuInfo, netInfo] in
            guard let self else { return }
            let memInfo = readMemory()
            let (isOpen, tick, hasHelper) = await MainActor.run(body: { (self.isPanelVisible, self.tickCount, self.helperOK) })
            let needFans = hasHelper && (isOpen || tick % 10 == 0)
            let output  = (isOpen && hasHelper) ? runHelper(["all"]) : (needFans ? runHelper(["read"]) : "")
            let parts   = output.components(separatedBy: "---\n")
            let fans    = needFans ? parseFans(parts.first ?? "") : []
            let sensors = (isOpen && hasHelper) ? parseSensors(parts.count > 1 ? parts[1] : "") : SensorData()
            let diskInfo = (isOpen && slow) ? readDisk() : nil
            let bat      = isOpen ? readBatteryPS() : nil
            let hdr      = (isOpen && slow) ? readSystemHeader() : nil

            await MainActor.run { [weak self] in
                guard let self else { return }
                let isOnAC = bat?.isOnAC ?? self.lastIsOnAC
                let isCharging = bat?.isCharging ?? false
                let batFull = (bat?.percent ?? self.lastBat?.percent ?? 0) >= 1.0
                let powerMode: Int = isOnAC ? ((isCharging || !batFull) ? 1 : 2) : 0
                let systemPowerW: Double = isOnAC ? (sensors.pdtr > 0 ? sensors.pdtr : sensors.pstr) : sensors.pstr

                if self.isPanelVisible {
                    self.batteryBarView.powerMode = powerMode
                    self.batteryBarView.pushSample(watts: systemPowerW)
                }
                if !fans.isEmpty {
                    self.avgRPM = fans.map(\.cur).reduce(0, +) / Double(fans.count)
                    self.fanIsManual = fans.contains { $0.mode == 1 }
                    self.updateIconRotation()
                }
                if isOpen { self.updateIconHot(cpu: sensors.cpuTemp, gpu: sensors.gpuTemp) }
                guard self.isPanelVisible else { return }

                if let hdr { self.headerView.modelName = hdr.modelName; self.headerView.uptimeLine = hdr.uptimeStr; self.headerView.display() }

                if let f = fans.first {
                    self.fanView.update(cur: f.cur, min: fans.map(\.min).min() ?? 1500, max: fans.map(\.max).max() ?? 4700, target: f.target, manual: self.fanIsManual)
                    self.fanView.push(rpm: self.avgRPM)
                }

                self.tempBarView.entries = [
                    .init(label: "CPU", value: sensors.cpuTemp, warnAt: 60, critAt: 95),
                    .init(label: "GPU", value: sensors.gpuTemp, warnAt: 60, critAt: 95),
                    .init(label: "电池", value: sensors.batteryTemp, warnAt: 35, critAt: 45, maxTemp: 60),
                ]; self.tempBarView.display()

                let gpuUtil = readGPUUtilization()
                self.metricBarView.entries = [
                    .init(label: "CPU", valueStr: String(format: "%.0f%%", cpuInfo.percent * 100), percent: cpuInfo.percent, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
                    .init(label: "GPU", valueStr: gpuUtil >= 0 ? String(format: "%.0f%%", gpuUtil * 100) : "--", percent: gpuUtil, color: .systemGreen, warnAt: 0.70, critAt: 0.90),
                    .init(label: "内存", valueStr: String(format: "%.0f%%", memInfo.percent * 100), percent: memInfo.percent, color: .systemBlue, warnAt: 0.60, critAt: 0.90),
                ]; self.metricBarView.display()

                self.netBarView.cols = [
                    .init(label: "下载", valueStr: formatBytes(netInfo.rxBytesPerSec), color: .systemTeal),
                    .init(label: "上传", valueStr: formatBytes(netInfo.txBytesPerSec), color: .systemTeal),
                ]; self.netBarView.display()

                if let d = diskInfo {
                    var rows: [MetricBarView.Entry] = [
                        .init(label: "已用", valueStr: String(format: "%.0f%%", d.percent * 100), percent: d.percent, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                    ]
                    if let s = self.smartInfo, s.ok {
                        let hColor: NSColor = s.health >= 90 ? .systemGreen
                                            : s.health >= 70 ? .systemOrange
                                            : .systemRed
                        rows.append(.init(label: "健康", valueStr: "\(s.health)%", percent: Double(s.health) / 100, color: hColor, warnAt: 2, critAt: 2))
                    }
                    self.diskBarView.entries = rows
                    self.diskBarView.display()
                }

                if let bat {
                    self.batteryBarView.isHidden = !bat.hasBattery; self.lastIsOnAC = bat.isOnAC
                    if bat.hasBattery { self.batteryBarView.percent = bat.percent; self.lastBat = bat }
                } else if let cached = self.lastBat { self.batteryBarView.isHidden = !cached.hasBattery }

                if let bat = self.lastBat {
                    let wattsStr = String(format: "%.1fW", systemPowerW)
                    self.batteryBarView.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                    self.efficiencyView.isOnBattery = (powerMode == 0)
                    if powerMode == 1 { self.batteryBarView.timeLine = wattsStr }
                    else if powerMode == 0 {
                        let tte = bat.timeToEmpty
                        self.batteryBarView.timeLine = tte > 0 ? "剩余续航 \(tte / 60)小时\(tte % 60)分  ·  \(wattsStr)" : wattsStr
                    } else {
                        let t = sensors.batteryTemp > 0 ? String(format: "  ·  %.1f°C", sensors.batteryTemp) : ""
                        self.batteryBarView.timeLine = bat.healthPercent > 0 ? String(format: "健康 %.0f%%  ·  %d 次循环%@", bat.healthPercent * 100, bat.cycleCount, t) : ""
                    }
                    self.batteryBarView.display()
                }
            }
        }
    }

    // MARK: - Icon

    func updateIconRotation() {
        withAnimation { iconModel.spinning = avgRPM >= 100 }
    }

    func updateIconHot(cpu: Double, gpu: Double) {
        withAnimation { iconModel.hot = max(cpu, gpu) >= 80 }
    }
}

@available(macOS 27.0, *)
extension AppController: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        showPanel()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        hidePanel()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.run()
}
