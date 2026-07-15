// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - System Bar View  (已废弃，代码保留备用)

final class SystemBarView: NSView {
    struct Row {
        var label: String
        var valueStr: String
        var percent: Double     // 0-1, <0 = no bar
        var color: NSColor
    }
    var rows: [Row] = []
    var sectionTitle: String = ""

    static let rowH:  CGFloat = 52
    static let headH: CGFloat = 16

    // rows==2 → 2-column single-row layout; rows==1 → single-row full-width
    static func height(rows: Int, hasTitle: Bool) -> CGFloat {
        let dataH: CGFloat = rowH   // always 1 visual row (2-col or 1-col)
        return dataH + (hasTitle ? headH : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        var y = bounds.height

        if !sectionTitle.isEmpty {
            y -= SystemBarView.headH
            NSAttributedString(string: sectionTitle, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: IP, y: y + 2))
        }

        let rowH = SystemBarView.rowH
        let rowTop = y - rowH
        if rows.count == 2 {
            let colW = (bounds.width - IP * 2) / 2
            for (i, row) in rows.enumerated() {
                let x = IP + CGFloat(i) * colW
                drawCell(row: row, x: x, rowTop: rowTop, colW: colW - 8)
            }
        } else if rows.count == 1 {
            drawCell(row: rows[0], x: IP, rowTop: rowTop, colW: bounds.width - IP * 2)
        }
    }

    private func drawCell(row: Row, x: CGFloat, rowTop: CGFloat, colW: CGFloat) {
        let valColor: NSColor = row.percent >= 0.95 ? .systemRed
                              : row.percent >= 0.85 ? .systemOrange
                              : row.color

        // Big value — 20pt mono semibold, colored, upper portion
        let valStr = NSAttributedString(string: row.valueStr, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: valColor
        ])
        valStr.draw(at: NSPoint(x: x, y: rowTop + SystemBarView.rowH - 28))

        // Label — 10pt regular secondaryLabelColor, below value
        NSAttributedString(string: row.label, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: x, y: rowTop + SystemBarView.rowH - 28 - 14))

        // Thin bar at bottom
        if row.percent >= 0 {
            let barY = rowTop + TR + 4
            let trackRect = NSRect(x: x, y: barY, width: colW, height: TR)
            let track = NSBezierPath(roundedRect: trackRect, xRadius: CR, yRadius: CR)
            NSColor.separatorColor.withAlphaComponent(0.25).setFill()
            track.fill()
            let fillW = max(TR, colW * CGFloat(row.percent))
            let fillRect = NSRect(x: x, y: barY, width: fillW, height: TR)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: CR, yRadius: CR)
            valColor.withAlphaComponent(0.7).setFill()
            fill.fill()
        }
    }
}

