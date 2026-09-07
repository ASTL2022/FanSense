// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import SwiftUI

/// 菜单栏图标三态（颜色管"模式"、字形管"转没转"）：
/// - `.idle`       — 风扇停转：白色风扇图标
/// - `.manualSpin` — 手动调速中：白色温度计（转速是用户自己设的，不代表机器热）
/// - `.autoSpin`   — 系统自动起转：红色温度计（系统判断需要散热，机器通常较热）
enum StatusIconState {
    case idle
    case manualSpin
    case autoSpin
}

@MainActor
final class IconModel: ObservableObject {
    @Published var state: StatusIconState = .idle
}

/// 纯静态切换，无动画。
struct StatusIconView: View {
    @ObservedObject var model: IconModel
    var body: some View {
        Image(systemName: model.state == .idle ? "fan.fill" : "thermometer.medium")
            .font(.system(size: 13, weight: .medium))
            .contentTransition(.opacity)
            .foregroundStyle(model.state == .autoSpin ? Color(nsColor: .systemRed) : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}
