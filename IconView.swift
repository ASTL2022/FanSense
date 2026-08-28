// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import SwiftUI

@MainActor
final class IconModel: ObservableObject {
    @Published var spinning = false
}

/// 菜单栏图标：风扇静止时显示风扇图标；电脑风扇开始转（转速≥阈值）时
/// 切换为温度计图标。纯静态切换，无动画。
struct StatusIconView: View {
    @ObservedObject var model: IconModel
    var body: some View {
        Image(systemName: model.spinning ? "thermometer.medium" : "fan.fill")
            .font(.system(size: 13, weight: .medium))
            .contentTransition(.opacity)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}
