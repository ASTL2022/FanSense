// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Efficiency Rating View

final class EfficiencyView: NSView {
    static let viewH: CGFloat = 68

    var avgWatts: Double = 0 { didSet { needsDisplay = true } }
    var timeToEmpty: Int = -1 { didSet { needsDisplay = true } }
    var isOnBattery: Bool = false { didSet { needsDisplay = true } }

    private var grade: Int {
        let wGrade = avgWatts < 10 ? 0 : avgWatts < 15 ? 1 : 2
        if !isOnBattery { return wGrade }
        let tGrade: Int
        if timeToEmpty <= 0 { tGrade = 0 }
        else if timeToEmpty >= 240 { tGrade = 0 }
        else if timeToEmpty >= 120 { tGrade = 1 }
        else { tGrade = 2 }
        return max(wGrade, tGrade)
    }

    private var gradeColor: NSColor {
        switch grade {
        case 0: return .systemGreen
        case 1: return .systemOrange
        default: return .systemRed
        }
    }

    private var gradeLabel: String {
        switch grade {
        case 0: return "高效"
        case 1: return "中等"
        default: return "高耗"
        }
    }

    override func draw(_ dirty: NSRect) {
        let W = bounds.width
        let cX = Layout.IP
        let cW = W - Layout.IP * 2
        let color = gradeColor

        let leftX    = cX
        let rightEdge = cX + cW

        // ── 进度条（最底层）──
        let barH: CGFloat = 6
        let barR: CGFloat = barH / 2
        let barY: CGFloat = barH / 2 + 4
        let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH),
                                 xRadius: barR, yRadius: barR)
        NSColor.separatorColor.withAlphaComponent(0.2).setFill()
        track.fill()
        if avgWatts > 0 {
            let fillW = max(barH, cW * CGFloat(min(avgWatts / 50.0, 1.0)))
            let fill = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: fillW, height: barH),
                                    xRadius: barR, yRadius: barR)
            color.withAlphaComponent(0.75).setFill()
            fill.fill()
        }

        // ── 副标签行（进度条上方 6pt）──
        let subFont = NSFont.systemFont(ofSize: 10)
        let subColor = NSColor.secondaryLabelColor
        let subY: CGFloat = barY + barH + 6

        NSAttributedString(string: "均值功耗", attributes: [
            .font: subFont, .foregroundColor: subColor
        ]).draw(at: NSPoint(x: leftX, y: subY))

        let subRAttr = NSAttributedString(string: "能效评级", attributes: [
            .font: subFont, .foregroundColor: subColor
        ])
        let subRSz = subRAttr.size()
        subRAttr.draw(at: NSPoint(x: rightEdge - subRSz.width, y: subY))

        // ── 主数值行（副标签上方 4pt）──
        let mainY: CGFloat = subY + 14 + 4
        let mainFont = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)

        // 左：功耗数字
        let wStr = avgWatts > 0 ? String(format: "%.1fW", avgWatts) : "--"
        NSAttributedString(string: wStr, attributes: [
            .font: mainFont, .foregroundColor: color
        ]).draw(at: NSPoint(x: leftX, y: mainY))

        // 右：等级文字 + 圆点
        let dotSize: CGFloat = 8
        let gradeAttr = NSAttributedString(string: gradeLabel, attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: color
        ])
        let gsz = gradeAttr.size()
        let gradeTextX = rightEdge - gsz.width
        let dotX = gradeTextX - dotSize - 5
        let dotY = mainY + (gsz.height - dotSize) / 2 + 1
        let dot = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize))
        color.setFill()
        dot.fill()
        gradeAttr.draw(at: NSPoint(x: gradeTextX, y: mainY))
    }
}

