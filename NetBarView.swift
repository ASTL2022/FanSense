// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Net Bar View  (网络，两列，标题+数值，无进度条无状态)

final class NetBarView: NSView {
    struct Col {
        var label:    String
        var valueStr: String
        var color:    NSColor
    }
    var cols: [Col] = [] { didSet { needsDisplay = true } }
    var sectionTitle: String = ""

    private static let headH: CGFloat = 16
    private static let rowH:  CGFloat = 56   // 与 MetricBarView.rowH 一致

    static func height() -> CGFloat { headH + rowH }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let cX = IP
        let cW = bounds.width - IP * 2

        // 区段标题（与 MetricBarView 相同坐标逻辑）
        if !sectionTitle.isEmpty {
            NSAttributedString(string: sectionTitle, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: bounds.height - NetBarView.headH + 2))
        }

        let rightEdge  = cX + cW
        // 内容区底部对齐：与 MetricBarView 单行 barY/mainY/titleY 相同
        let rowBottom  = bounds.height - NetBarView.headH - NetBarView.rowH
        let barH:  CGFloat = 5
        let mainY  = rowBottom + barH + 4 + 4     // barY(4)+barH(5)+gap(4) — 对齐 MetricBarView
        let titleY = mainY + 25 + 3

        let titleFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let mainFont  = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)

        // 下载：左对齐；上传：右对齐
        for (i, col) in cols.prefix(2).enumerated() {
            let valAttr = NSAttributedString(string: col.valueStr, attributes: [
                .font: mainFont, .foregroundColor: col.color
            ])
            let lblAttr = NSAttributedString(string: col.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.tertiaryLabelColor
            ])

            let valX: CGFloat = i == 0 ? cX : rightEdge - valAttr.size().width
            let lblX: CGFloat = i == 0 ? cX : rightEdge - lblAttr.size().width

            valAttr.draw(at: NSPoint(x: valX, y: mainY))
            lblAttr.draw(at: NSPoint(x: lblX, y: titleY))
        }
    }
}

