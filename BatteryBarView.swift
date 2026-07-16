// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Battery Bar View

final class BatteryBarView: NSView {
    var percent: Double = 0
    var timeLine: String = "--"
    var powerMode: Int = 0           // 0=discharging, 1=charging, 2=full
    var isLowPower: Bool = false     // 节电模式 → 橙色

    static let h: CGFloat = 244   // topPad(20) + rowH(56) + gap(12) + chart(144) + botPad(12)

    private let topPadV: CGFloat = 20
    private let rowH:    CGFloat = 56

    private let chart = ChargeChartView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(chart)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let dataTop = bounds.height - topPadV - rowH
        let chartH = dataTop - 12
        chart.frame = NSRect(x: 8, y: 10,
                             width: bounds.width - 16,
                             height: max(chartH - 10, 0))
    }

    func pushSample(watts: Double) {
        chart.powerMode = powerMode
        chart.push(watts: watts)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let cX = IP
        let cW = bounds.width - IP * 2
        let rightEdge = cX + cW

        let contentH = bounds.height - topPadV
        let rowBottom: CGFloat = contentH - rowH

        let subText: String = (powerMode == 2) ? "" : timeLine
        let infoH: CGFloat = subText.isEmpty ? 0 : 14

        // ── 电池进度条（同 TempBarView barY = rowBottom + 4）──
        let barH: CGFloat = 12, barR = barH / 2
        let barY: CGFloat = rowBottom + 4
        let barW = cW - 3 - 1
        let outlineRect = NSRect(x: cX, y: barY, width: barW, height: barH)
        barColor().withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: outlineRect, xRadius: barR, yRadius: barR).lineWidth = 1.5
        NSBezierPath(roundedRect: outlineRect, xRadius: barR, yRadius: barR).stroke()
        let inset: CGFloat = 2
        let fillW = max(barR, (barW - inset * 2) * CGFloat(min(max(percent, 0), 1)))
        let fillRect = NSRect(x: cX + inset, y: barY + inset, width: fillW, height: barH - inset * 2)
        barColor().setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: barR - inset, yRadius: barR - inset).fill()
        let nipRect = NSRect(x: cX + barW + 1, y: barY + 3, width: 3, height: 6)
        barColor().withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: nipRect, xRadius: 1, yRadius: 1).fill()

        // ── 副信息文字 ──
        if !subText.isEmpty {
            NSAttributedString(string: subText, attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.labelColor
            ]).draw(at: NSPoint(x: cX, y: barY + barH + 4))
        }

        // ── 主数值 + 状态 ──
        let mainFont = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        let statFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let mainY: CGFloat = barY + barH + infoH + 4

        // 左侧：百分比
        NSAttributedString(string: String(format: "%.0f%%", percent * 100), attributes: [
            .font: mainFont, .foregroundColor: barColor()
        ]).draw(at: NSPoint(x: cX, y: mainY))

        // 右侧：状态文字
        let (statStr, statColor): (String, NSColor) = {
            switch powerMode {
            case 0: return isLowPower
                ? ("节电", NSColor(red: 247/255, green: 206/255, blue: 70/255, alpha: 1))
                : ("放电中", .systemYellow)
            case 1: return ("充电中", .systemGreen)
            default: return ("满电供电", .systemBlue)
            }
        }()
        let statAttr = NSAttributedString(string: statStr, attributes: [
            .font: statFont, .foregroundColor: statColor
        ])
        statAttr.draw(at: NSPoint(x: rightEdge - statAttr.size().width, y: mainY))

        // 充电闪电图标
        if powerMode == 1, let bolt = NSImage(systemSymbolName: "bolt.fill",
                accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)) {
            let bsz = bolt.size
            let bx = rightEdge - statAttr.size().width - bsz.width - 3
            let by = mainY + (statAttr.size().height - bsz.height) / 2 + 2
            let tinted = NSImage(size: bsz, flipped: false) { r in
                statColor.setFill(); r.fill()
                bolt.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)
                return true
            }
            tinted.draw(in: NSRect(x: bx, y: by, width: bsz.width, height: bsz.height))
        }
    }

    private func barColor() -> NSColor {
        switch powerMode {
        case 1: return .systemGreen  // 充电中
        case 2: return .systemBlue   // 满电供电
        default:
            if percent < 0.2 { return .systemRed }  // 低电量
            if isLowPower {
                return NSColor(red: 247/255, green: 206/255, blue: 70/255, alpha: 1)
            }
            return .systemGreen
        }
    }
}

