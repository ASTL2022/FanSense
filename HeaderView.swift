// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Header View

final class HeaderView: NSView {
    var modelName: String = ""
    var uptimeLine: String = ""

    static let h: CGFloat = 48

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        // Model name — 15pt medium labelColor, centered
        let nameAttr = NSAttributedString(string: modelName, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        let nsz = nameAttr.size()
        nameAttr.draw(at: NSPoint(x: (bounds.width - nsz.width) / 2,
                                  y: bounds.height / 2 + 2))

        // Uptime — 11pt regular secondaryLabelColor, centered below
        let upAttr = NSAttributedString(string: uptimeLine, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let usz = upAttr.size()
        upAttr.draw(at: NSPoint(x: (bounds.width - usz.width) / 2,
                                y: bounds.height / 2 - usz.height - 2))
    }
}

