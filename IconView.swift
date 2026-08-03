// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import SwiftUI

@MainActor
final class IconModel: ObservableObject {
    @Published var spinning = false
}

struct StatusIconView: View {
    @ObservedObject var model: IconModel
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var body: some View {
        Image(systemName: reduceMotion ? "fan" : "fan.fill")
            .font(.system(size: 13, weight: .medium))
            .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: model.spinning && !reduceMotion)
            .contentTransition(.opacity)
            .foregroundStyle(.primary)
            .opacity(reduceMotion && model.spinning ? 0.6 : 1.0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}
