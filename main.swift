// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let fanService = FanControlService()
    let panelController = PanelController()
    let iconModel = IconModel()

    let powerAlertService = PowerAlertService()

    var dataTimer: Timer?
    var sliderDebounce: Timer?
    var tickCount: Int = 0
    var refreshInFlight = false

    var smartInfo: SmartInfo?
    var lastIsOnAC: Bool = true
    var lastBat: BatteryInfo?

    var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64) = (0, 0, 0)
    var prevNetBytes: (rx: UInt64, tx: UInt64, time: Double) = (0, 0, 0)

    override init() {
        super.init()
        fanService.onRefreshNeeded = { [weak self] in
            guard let self else { return }
            self.panelController.fanView.pendingChange = false
            self.refresh(force: true)
        }
        powerAlertService.onSampleUpdate = { [weak self] w, t, b, _ in
            guard let self else { return }
            self.panelController.efficiencyView.avgWatts = w
            self.panelController.efficiencyView.timeToEmpty = t
            self.panelController.efficiencyView.isOnBattery = b
            self.panelController.efficiencyView.display()
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupIcon()

        initViewData()
        panelController.setup(statusButton: statusItem.button)

        panelController.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.dataTimer?.invalidate()
            let interval = visible ? 1.0 : 30.0
            self.dataTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.tickCount += 1
                    self.refresh(slow: self.tickCount % 30 == 0)
                    if self.tickCount % 60 == 0 { self.fanService.checkHelper() }
                }
            }
        }

        fanService.checkHelper()
        fanService.ensureHelper()
        readSmartOnce()
        refresh(slow: true, force: true)

        let initialInterval = panelController.isVisible ? 1.0 : 30.0
        dataTimer = Timer.scheduledTimer(withTimeInterval: initialInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickCount += 1
                self.refresh(slow: self.tickCount % 30 == 0)
                if self.tickCount % 60 == 0 { self.fanService.checkHelper() }
            }
        }

        powerAlertService.startBGTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fanService.bestEffortAuto()
    }

    // MARK: - Status Item

    func setupIcon() {
        guard let btn = statusItem.button else { return }
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        btn.toolTip = "FanSense \(ver)"
        let host = NSHostingView(rootView: StatusIconView(model: iconModel))
        host.frame = btn.bounds
        host.autoresizingMask = [.width, .height]
        btn.addSubview(host)
        btn.target = self
        btn.action = #selector(statusClicked)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func statusClicked() {
        guard let event = NSApp.currentEvent else { return }
        let isContextClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isContextClick {
            showContextMenu()
        } else if event.type == .leftMouseUp, event.clickCount == 1 {
            panelController.toggle()
            if panelController.isVisible { refresh(slow: true, force: true) }
        }
    }

    func showContextMenu() {
        guard let btn = statusItem.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: -1, y: -4), in: btn)
    }

    @objc func quitApp() { fanService.bestEffortAuto(); NSApp.terminate(nil) }

    // MARK: - Views Init

    func initViewData() {
        let pc = panelController
        pc.tempBarView.sectionTitle = "温度"
        pc.tempBarView.entries = [
            .init(label: "CPU",  value: 0, warnAt: 60, critAt: 95),
            .init(label: "GPU",  value: 0, warnAt: 60, critAt: 95),
            .init(label: "电池", value: 0, warnAt: 35, critAt: 45, maxTemp: 60),
        ]
        pc.metricBarView.sectionTitle = "占用"
        pc.metricBarView.entries = [
            .init(label: "CPU",  valueStr: "--", percent: 0, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
            .init(label: "GPU",  valueStr: "--", percent: 0, color: .systemGreen,  warnAt: 0.70, critAt: 0.90),
            .init(label: "内存", valueStr: "--", percent: 0, color: .systemBlue,   warnAt: 0.60, critAt: 0.90),
        ]
        pc.netBarView.sectionTitle = "网络"
        pc.netBarView.cols = [
            .init(label: "下载", valueStr: "--", color: .systemTeal),
            .init(label: "上传", valueStr: "--", color: .systemTeal),
        ]
        pc.diskBarView.sectionTitle = "磁盘"
        pc.diskBarView.entries = [
            .init(label: "已用", valueStr: "--", percent: 0,  color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
            .init(label: "健康", valueStr: "--", percent: 0,  color: .systemGreen,  showStatus: false),
        ]
        pc.fanView.onSliderChange = { [weak self] rpm in
            guard let self else { return }
            self.sliderDebounce?.invalidate()
            self.sliderDebounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.fanService.helperOK else {
                        self.panelController.fanView.pendingChange = false; return
                    }
                    if rpm <= self.panelController.fanView.minRPM + 1 {
                        self.fanService.restoreAuto()
                    } else {
                        self.fanService.setFanSpeed(Int(rpm))
                    }
                }
            }
        }
    }

    // MARK: - Data

    func readSmartOnce() {
        guard fanService.helperOK else { return }
        Task.detached { [weak self] in
            let info = parseSmart(runHelper(["smart"]))
            await MainActor.run { [weak self] in self?.smartInfo = info }
        }
    }

    // MARK: - Data Refresh

    func refresh(slow: Bool = false, force: Bool = false) {
        guard force || !refreshInFlight else { return }
        let visible = panelController.isVisible
        refreshInFlight = true
        let cpuInfo = visible ? readCPU(prevTicks: &prevCPUTicks) : CPUInfo()
        let netInfo = visible ? readNetwork(prevBytes: &prevNetBytes) : NetworkInfo()

        Task.detached { [weak self, cpuInfo, netInfo] in
            guard let self else { return }
            let memInfo = visible ? readMemory() : MemoryInfo()
            let (isOpen, hasHelper) = await MainActor.run(body: {
                (self.panelController.isVisible, self.fanService.helperOK)
            })
            let output  = hasHelper ? runHelper(isOpen ? ["all"] : ["read"]) : ""
            let parts   = output.components(separatedBy: "---\n")
            let fans    = hasHelper ? parseFans(parts.first ?? "") : []
            let sensors = (isOpen && hasHelper) ? parseSensors(parts.count > 1 ? parts[1] : "") : SensorData()
            let diskInfo = (isOpen && slow) ? readDisk() : nil
            let bat      = isOpen ? readBatteryPS() : nil
            let hdr      = (isOpen && slow) ? readSystemHeader() : nil

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.refreshInFlight = false }
                let isOnAC = bat?.isOnAC ?? self.lastIsOnAC
                let isCharging = bat?.isCharging ?? false
                let batFull = (bat?.percent ?? self.lastBat?.percent ?? 0) >= 1.0

                if let bat, self.lastIsOnAC && !bat.isOnAC {
                    self.powerAlertService.detectACTransition(bat: bat)
                }
                let inPowerTransition = self.powerAlertService.powerTransitionUntil.map { Date() < $0 } ?? false
                let powerMode: Int = isOnAC ? ((isCharging || !batFull) ? 1 : 2) : 0
                let systemPowerW: Double = isOnAC ? (sensors.pdtr > 0 ? sensors.pdtr : sensors.pstr) : sensors.pstr

                if self.panelController.isVisible {
                    self.panelController.batteryBarView.powerMode = powerMode
                    self.panelController.batteryBarView.pushSample(watts: systemPowerW)
                }

                if !fans.isEmpty {
                    self.fanService.avgRPM = fans.map(\.cur).reduce(0, +) / Double(fans.count)
                    self.fanService.syncMode(from: fans, pendingChange: self.panelController.fanView.pendingChange)
                    self.updateIconRotation()
                }

                guard self.panelController.isVisible else { return }

                if let hdr {
                    self.panelController.headerView.modelName = hdr.modelName
                    self.panelController.headerView.uptimeLine = hdr.uptimeStr
                    self.panelController.headerView.display()
                }

                if let f = fans.first {
                    self.panelController.fanView.update(
                        cur: f.cur, min: fans.map(\.min).min() ?? 1500,
                        max: fans.map(\.max).max() ?? 4700, target: f.target,
                        mode: self.fanService.fanMode, smcManual: self.fanService.smcManual)
                    self.panelController.fanView.push(rpm: self.fanService.avgRPM)
                }

                self.panelController.tempBarView.entries = [
                    .init(label: "CPU", value: sensors.cpuTemp, warnAt: 60, critAt: 95),
                    .init(label: "GPU", value: sensors.gpuTemp, warnAt: 60, critAt: 95),
                    .init(label: "电池", value: sensors.batteryTemp, warnAt: 35, critAt: 45, maxTemp: 60),
                ]; self.panelController.tempBarView.display()

                let gpuUtil = readGPUUtilization()
                self.panelController.metricBarView.entries = [
                    .init(label: "CPU", valueStr: String(format: "%.0f%%", cpuInfo.percent * 100), percent: cpuInfo.percent, color: .systemPurple, warnAt: 0.70, critAt: 0.90),
                    .init(label: "GPU", valueStr: gpuUtil >= 0 ? String(format: "%.0f%%", gpuUtil * 100) : "--", percent: gpuUtil, color: .systemGreen, warnAt: 0.70, critAt: 0.90),
                    .init(label: "内存", valueStr: String(format: "%.0f%%", memInfo.percent * 100), percent: memInfo.percent, color: .systemBlue, warnAt: 0.60, critAt: 0.90),
                ]; self.panelController.metricBarView.display()

                self.panelController.netBarView.cols = [
                    .init(label: "下载", valueStr: formatBytes(netInfo.rxBytesPerSec), color: .systemTeal),
                    .init(label: "上传", valueStr: formatBytes(netInfo.txBytesPerSec), color: .systemTeal),
                ]; self.panelController.netBarView.display()

                if let d = diskInfo {
                    var rows: [MetricBarView.Entry] = [
                        .init(label: "已用", valueStr: String(format: "%.0f%%", d.percent * 100), percent: d.percent, color: .systemIndigo, warnAt: 0.80, critAt: 0.90),
                    ]
                    if let s = self.smartInfo, s.ok {
                        let hColor: NSColor = s.health >= 90 ? .systemGreen
                                            : s.health >= 70 ? .systemOrange
                                            : .systemRed
                        rows.append(.init(label: "健康", valueStr: "\(s.health)%", percent: Double(s.health) / 100, color: hColor, showStatus: false))
                    }
                    self.panelController.diskBarView.entries = rows
                    self.panelController.diskBarView.display()
                }

                if let bat {
                    self.panelController.batteryBarView.isHidden = !bat.hasBattery
                    self.lastIsOnAC = bat.isOnAC
                    if bat.hasBattery {
                        self.panelController.batteryBarView.percent = bat.percent
                        self.lastBat = bat
                        self.powerAlertService.lastIsOnAC = bat.isOnAC
                        self.powerAlertService.lastBat = bat
                    }
                } else if let cached = self.lastBat {
                    self.panelController.batteryBarView.isHidden = !cached.hasBattery
                }

                if let bat = self.lastBat {
                    if inPowerTransition {
                        self.panelController.batteryBarView.timeLine = "⚡ 正在计算续航…"
                        self.panelController.batteryBarView.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                        self.panelController.efficiencyView.isOnBattery = (powerMode == 0)
                    } else {
                        let wattsStr = String(format: "%.1fW", systemPowerW)
                        self.panelController.batteryBarView.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                        self.panelController.efficiencyView.isOnBattery = (powerMode == 0)
                        if powerMode == 1 {
                            self.panelController.batteryBarView.timeLine = wattsStr
                        } else if powerMode == 0 {
                            let tte = bat.timeToEmpty > 0 ? bat.timeToEmpty : estimateTimeToEmpty(from: sensors)
                            self.panelController.batteryBarView.timeLine = tte > 0 ? "剩余续航 \(tte / 60)小时\(tte % 60)分  ·  \(wattsStr)" : wattsStr
                        } else {
                            let t = sensors.batteryTemp > 0 ? String(format: "  ·  %.1f°C", sensors.batteryTemp) : ""
                            self.panelController.batteryBarView.timeLine = bat.healthPercent > 0 ? String(format: "健康 %.0f%%  ·  %d 次循环%@", bat.healthPercent * 100, bat.cycleCount, t) : ""
                        }
                    }
                    self.panelController.batteryBarView.display()
                }
            }
        }
    }

    // MARK: - Icon

    func updateIconRotation() {
        let spinning = fanService.avgRPM >= 100
        guard spinning != iconModel.spinning else { return }
        withAnimation { iconModel.spinning = spinning }
    }
}

// MARK: - Entry Point

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.run()
}
