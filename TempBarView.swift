import Cocoa

// MARK: - Temperature Bar View

final class TempBarView: NSView {
    struct Entry {
        var label: String
        var value: Double
        var warnAt: Double
        var critAt: Double
        var maxTemp: Double = 105
    }
    var entries: [Entry] = [] { didSet { needsDisplay = true } }
    var sectionTitle: String = ""

    static let rowH:  CGFloat = 56
    static let rowGap: CGFloat = 8
    static let headH: CGFloat = 16

    static func height(count: Int = 3) -> CGFloat {
        headH + CGFloat(count) * rowH + CGFloat(max(count - 1, 0)) * rowGap
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard !entries.isEmpty else { return }

        let cX        = IP
        let cW        = bounds.width - IP * 2
        let rightEdge = cX + cW
        let headH     = TempBarView.headH
        let rowH      = TempBarView.rowH
        let rowGap    = TempBarView.rowGap

        // ── 区段标题 ──
        if !sectionTitle.isEmpty {
            NSAttributedString(string: sectionTitle, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))
        }

        let barH:  CGFloat = 5
        let barR:  CGFloat = barH / 2
        let titleFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let mainFont  = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        let statFont  = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            let tempColor: NSColor = e.value >= e.critAt ? .systemRed
                                   : e.value >= e.warnAt ? .systemOrange
                                   : .systemBlue
            let statColor: NSColor = e.value >= e.critAt ? .systemRed
                                   : e.value >= e.warnAt ? .systemOrange
                                   : .systemGreen
            let statStr: String    = e.value >= e.critAt ? "降频"
                                   : e.value >= e.warnAt ? "高温"
                                   : "正常"

            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH

            let barY   = rowBottom + 4
            let mainY  = barY + barH + 4
            let titleY = mainY + 25 + 3

            NSAttributedString(string: e.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: titleY))

            let valStr = e.value > 0 ? String(format: "%.0f°", e.value) : "--"
            NSAttributedString(string: valStr, attributes: [
                .font: mainFont, .foregroundColor: tempColor
            ]).draw(at: NSPoint(x: cX, y: mainY))

            let statAttr = NSAttributedString(string: statStr, attributes: [
                .font: statFont, .foregroundColor: statColor
            ])
            statAttr.draw(at: NSPoint(x: rightEdge - statAttr.size().width, y: mainY + 2))

            let pct   = min(max(e.value / e.maxTemp, 0), 1)
            let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH),
                                     xRadius: barR, yRadius: barR)
            NSColor.separatorColor.withAlphaComponent(0.2).setFill()
            track.fill()
            if e.value > 0 {
                let fillW = max(barH, cW * CGFloat(pct))
                let fill  = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: fillW, height: barH),
                                          xRadius: barR, yRadius: barR)
                tempColor.withAlphaComponent(0.75).setFill()
                fill.fill()
            }
        }
    }
}

