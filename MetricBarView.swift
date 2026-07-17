// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Metric Bar View  (处理器·内存，竖排，标题+数值+状态+进度条)

final class MetricBarView: NSView {
    struct Entry {
        var label:    String
        var valueStr: String
        var percent:  Double    // 0-1
        var color:    NSColor   // 正常色
        var warnAt:   Double = 0.70   // percent 阈值（橙）
        var critAt:   Double = 0.90   // percent 阈值（红）
        var showStatus: Bool = true   // 为 false 时不显示状态文字，直接用 entry.color
    }
    var entries: [Entry] = [] { didSet { needsDisplay = true } }
    var sectionTitle: String = ""

    private static let rowH:  CGFloat = 56
    private static let rowGap: CGFloat = 8
    private static let headH: CGFloat = 16

    static func height(count: Int) -> CGFloat {
        headH + CGFloat(count) * rowH + CGFloat(max(count - 1, 0)) * rowGap
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let cX        = IP
        let cW        = bounds.width - IP * 2
        let rightEdge = cX + cW
        let rowH      = MetricBarView.rowH
        let rowGap    = MetricBarView.rowGap
        let headH     = MetricBarView.headH

        // ── 区段标题 ──
        if !sectionTitle.isEmpty {
            NSAttributedString(string: sectionTitle, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))
        }

        let barH:  CGFloat = 5
        let barR:  CGFloat = barH / 2
        let titleFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let mainFont  = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        let statFont  = NSFont.systemFont(ofSize: 22, weight: .semibold)

        for (i, e) in entries.enumerated() {
            let valColor: NSColor
            let statColor: NSColor
            let statStr: String
            if e.showStatus {
                valColor  = e.percent >= e.critAt ? .systemRed
                          : e.percent >= e.warnAt ? .systemOrange
                          : e.color
                statColor = e.percent >= e.critAt ? .systemRed
                          : e.percent >= e.warnAt ? .systemOrange
                          : .systemGreen
                statStr   = e.percent >= e.critAt ? "过载"
                          : e.percent >= e.warnAt ? "较高"
                          : "正常"
            } else {
                valColor  = e.color
                statColor = e.color
                statStr   = ""
            }

            let contentH = bounds.height - headH
            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH

            let barY   = rowBottom + 4
            let mainY  = barY + barH + 4
            let titleY = mainY + 25 + 3

            // 小标题
            NSAttributedString(string: e.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: titleY))

            // 主数值（左）
            NSAttributedString(string: e.valueStr, attributes: [
                .font: mainFont, .foregroundColor: valColor
            ]).draw(at: NSPoint(x: cX, y: mainY))

            // 状态文字（右）
            if !statStr.isEmpty {
                let statAttr = NSAttributedString(string: statStr, attributes: [
                    .font: statFont, .foregroundColor: statColor
                ])
                statAttr.draw(at: NSPoint(x: rightEdge - statAttr.size().width, y: mainY))
            }

            // 进度条
            let pct   = min(max(e.percent, 0), 1)
            let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH),
                                     xRadius: barR, yRadius: barR)
            NSColor.separatorColor.withAlphaComponent(0.2).setFill()
            track.fill()
            let fillW = max(barH, cW * CGFloat(pct))
            let fill  = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: fillW, height: barH),
                                      xRadius: barR, yRadius: barR)
            valColor.withAlphaComponent(0.75).setFill()
            fill.fill()
        }
    }
}

