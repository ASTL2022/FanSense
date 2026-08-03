// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Foundation
import AppKit

// MARK: - Fan Mode

enum FanMode {
    case auto
    case manual
}

// MARK: - Fan Control Service

@MainActor
final class FanControlService {
    static let helperVersion = "4"

    var helperOK = false
    var avgRPM: Double = 0
    var fanMode: FanMode = .auto
    var smcManual: Bool = false
    var writeInFlight = 0
    private(set) var setGeneration = 0

    var onModeChanged: ((FanMode) -> Void)?
    var onRefreshNeeded: (() -> Void)?

    func checkHelper() {
        helperOK = FileManager.default.isExecutableFile(atPath: HELPER)
    }

    func ensureHelper() {
        let installed = FileManager.default.isExecutableFile(atPath: HELPER)
        if installed,
           runHelper(["version"]).trimmingCharacters(in: .whitespacesAndNewlines) == Self.helperVersion {
            helperOK = true
            return
        }
        checkHelper()
    }

    // MARK: - Fan Control Writes

    func restoreAuto() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        setGeneration += 1
        let gen = setGeneration
        fanMode = .auto
        writeInFlight += 1
        Task.detached { [weak self] in
            runHelper(["auto"])
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.writeInFlight -= 1
                if gen == self.setGeneration { self.onRefreshNeeded?() }
            }
        }
    }

    func setFanSpeed(_ rpm: Int) {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        setGeneration += 1
        let gen = setGeneration
        fanMode = .manual
        writeInFlight += 1
        Task.detached { [weak self] in
            guard let self else { return }
            let confirmed = await self.writeFanSpeed(gen: gen, rpm: rpm)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.writeInFlight -= 1
                guard gen == self.setGeneration else { return }
                if !confirmed { NSLog("FanSense: set \(rpm) rpm failed after retries") }
                self.onRefreshNeeded?()
            }
        }
    }

    // MARK: - Private Write Logic

    private func writeFanSpeed(gen: Int, rpm: Int) async -> Bool {
        for attempt in 0..<3 {
            guard await MainActor.run(body: { self.setGeneration == gen }) else { return false }
            let fans = parseFans(runHelper(["set", String(rpm)]))
            if fans.contains(where: { $0.mode == 1 }) { return true }
            NSLog("FanSense: set \(rpm) rpm not confirmed (attempt \(attempt + 1))")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - Mode Sync

    func syncMode(from fans: [FanState], pendingChange: Bool = false) {
        smcManual = fans.contains { $0.mode == 1 }
        guard writeInFlight == 0, !pendingChange else { return }
        if !smcManual && fanMode != .auto {
            fanMode = .auto
        } else if smcManual && fanMode == .auto {
            fanMode = .manual
        }
    }

    func bestEffortAuto() {
        guard helperOK else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: HELPER)
        p.arguments = ["auto"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }
}
