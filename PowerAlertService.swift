// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Foundation
@preconcurrency import UserNotifications

// MARK: - Power Alert Service

@MainActor
final class PowerAlertService {
    private var bgSampleTimer: Timer?
    private var powerSamples: [Double] = []
    private var lastNotifyTime: Date?

    var lastSensorData: SensorData = SensorData()
    var lastSensorTime: Date?
    var lastIsOnAC: Bool = true
    var powerTransitionUntil: Date?
    var lastBat: BatteryInfo?

    var onSampleUpdate: ((_ avgWatts: Double, _ timeToEmpty: Int, _ isOnBattery: Bool, _ inTransition: Bool) -> Void)?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func startBGTimer() {
        let t = Timer(fire: Date().addingTimeInterval(3), interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        bgSampleTimer = t
    }

    func sample() {
        Task.detached { [weak self] in
            guard let self else { return }
            let battery = readBatteryPS()
            let sensors: SensorData
            if battery.hasBattery && !battery.isOnAC {
                sensors = await smcMonitor.readSensors()
            } else {
                sensors = SensorData()
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let wasOnAC = self.lastIsOnAC
                self.lastBat = battery
                self.lastIsOnAC = battery.isOnAC
                if wasOnAC && !battery.isOnAC {
                    self.powerTransitionUntil = Date().addingTimeInterval(25)
                }
                if battery.isOnAC || sensors.pstr > 0 {
                    self.lastSensorData = sensors
                    self.lastSensorTime = Date()
                }
                let inTransition = self.powerTransitionUntil.map { Date() < $0 } ?? false
                if !battery.isOnAC && !inTransition {
                    let w = sensors.pstr > 0 ? sensors.pstr : 0
                    self.powerSamples.append(w)
                    if self.powerSamples.count > 5 { self.powerSamples.removeFirst() }
                }
                let avg = self.powerSamples.isEmpty ? 0.0 : self.powerSamples.reduce(0, +) / Double(self.powerSamples.count)
                let tte = effectiveTimeToEmpty(bat: battery, sensors: sensors)
                self.onSampleUpdate?(avg, tte, !battery.isOnAC, false)
                if !inTransition { self.checkPowerAlert() }
            }
        }
    }

    private func checkPowerAlert() {
        guard !lastIsOnAC, powerSamples.count == 5 else { return }
        let avg = powerSamples.reduce(0, +) / 5.0
        guard avg >= 15 else { return }
        let tte = effectiveTimeToEmpty(bat: lastBat, sensors: lastSensorData)
        guard tte > 0, tte < 180 else { return }
        if let last = lastNotifyTime, Date().timeIntervalSince(last) < 1800 { return }
        lastNotifyTime = Date()
        sendPowerAlert(avgW: avg, minutesLeft: tte)
    }

    private func sendPowerAlert(avgW: Double, minutesLeft: Int) {
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

    func detectACTransition(bat: BatteryInfo) {
        if lastIsOnAC && !bat.isOnAC {
            powerTransitionUntil = Date().addingTimeInterval(25)
        }
    }
}
