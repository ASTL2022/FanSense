import Cocoa

// MARK: - Temperature Card

final class TemperatureCard: NSView {
    struct Entry {
        var label: String
        var value: Double
        var warnAt: Double
        var critAt: Double
        var maxTemp: Double = 105
    }
    var entries: [Entry] = [] {
        didSet { updateBarLayers(); needsDisplay = true }
    }

    private var barLayers: [CALayer] = []
    private var layersReady = false

    static func height(count: Int = 3) -> CGFloat {
        Layout.sectionHeadH + CGFloat(count) * Layout.rowHeight + CGFloat(max(count - 1, 0)) * Layout.rowGap
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<3 {
            let l = CALayer()
            l.cornerRadius = Layout.barRadius
            l.masksToBounds = true
            barLayers.append(l)
            layer?.addSublayer(l)
        }
        layersReady = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); updateBarLayers() }

    private func updateBarLayers() {
        guard layersReady, !entries.isEmpty else { return }
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2
        let barH = Layout.barHeight, headH = Layout.sectionHeadH
        let rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            guard i < barLayers.count else { continue }
            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4
            let color: NSColor = e.value >= e.critAt ? .systemRed
                               : e.value >= e.warnAt ? .systemOrange
                               : .systemBlue
            let frac = e.value > 0 ? min(max(e.value / e.maxTemp, 0), 1) : 0
            let fillW = max(barH, cW * CGFloat(frac))
            barLayers[i].frame = CGRect(x: cX, y: barY, width: fillW, height: barH)
            barLayers[i].backgroundColor = color.withAlphaComponent(0.75).cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        guard !entries.isEmpty else { return }

        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW
        let barH = Layout.barHeight, barR = Layout.barRadius
        let headH = Layout.sectionHeadH, rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let mainFont = Typography.bigValue(), titleFont = Typography.section(), statFont = Typography.state()

        NSAttributedString(string: "温度", attributes: [
            .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))

        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            let color: NSColor = e.value >= e.critAt ? .systemRed
                               : e.value >= e.warnAt ? .systemOrange
                               : .systemBlue
            let statStr = e.value >= e.critAt ? "降频" : e.value >= e.warnAt ? "高温" : "正常"
            let statColor: NSColor = e.value >= e.critAt ? .systemRed
                                   : e.value >= e.warnAt ? .systemOrange
                                   : .systemGreen

            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4, mainY = barY + barH + 4, titleY = mainY + 25 + 3

            NSAttributedString(string: e.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: titleY))

            let valStr = e.value > 0 ? String(format: "%.0f°", e.value) : "--"
            NSAttributedString(string: valStr, attributes: [
                .font: mainFont, .foregroundColor: color
            ]).draw(at: NSPoint(x: cX, y: mainY))

            let sa = NSAttributedString(string: statStr, attributes: [
                .font: statFont, .foregroundColor: statColor
            ])
            sa.draw(at: NSPoint(x: rightEdge - sa.size().width, y: mainY + 2))

            let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH), xRadius: barR, yRadius: barR)
            NSColor.separatorColor.withAlphaComponent(0.2).setFill(); track.fill()
        }
    }
}

// MARK: - Usage Card (CPU / GPU / Memory)

final class UsageCard: NSView {
    struct Entry {
        var label: String; var valueStr: String; var percent: Double; var color: NSColor
        var warnAt: Double; var critAt: Double
    }
    var entries: [Entry] = [] {
        didSet { updateBarLayers(); needsDisplay = true }
    }

    private var barLayers: [CALayer] = []
    private var layersReady = false

    static func height(count: Int) -> CGFloat {
        Layout.sectionHeadH + CGFloat(count) * Layout.rowHeight + CGFloat(max(count - 1, 0)) * Layout.rowGap
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<3 {
            let l = CALayer(); l.cornerRadius = Layout.barRadius; l.masksToBounds = true
            barLayers.append(l); layer?.addSublayer(l)
        }
        layersReady = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); updateBarLayers() }

    private func updateBarLayers() {
        guard layersReady, !entries.isEmpty else { return }
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2
        let barH = Layout.barHeight, headH = Layout.sectionHeadH
        let rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            guard i < barLayers.count else { continue }
            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4
            let color: NSColor = e.percent >= e.critAt ? .systemRed
                               : e.percent >= e.warnAt ? .systemOrange : e.color
            let fillW = max(barH, cW * CGFloat(min(max(e.percent, 0), 1)))
            barLayers[i].frame = CGRect(x: cX, y: barY, width: fillW, height: barH)
            barLayers[i].backgroundColor = color.withAlphaComponent(0.75).cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()

        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW
        let barH = Layout.barHeight, barR = Layout.barRadius
        let headH = Layout.sectionHeadH, rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let mainFont = Typography.bigValue(), titleFont = Typography.section(), statFont = Typography.state()

        NSAttributedString(string: "占用", attributes: [
            .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))

        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            let valColor: NSColor = e.percent >= e.critAt ? .systemRed
                                  : e.percent >= e.warnAt ? .systemOrange
                                  : e.color
            let statColor: NSColor = e.percent >= e.critAt ? .systemRed
                                   : e.percent >= e.warnAt ? .systemOrange
                                   : .systemGreen
            let statStr = e.percent >= e.critAt ? "过载" : e.percent >= e.warnAt ? "较高" : "正常"

            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4, mainY = barY + barH + 4, titleY = mainY + 25 + 3

            NSAttributedString(string: e.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: titleY))
            NSAttributedString(string: e.valueStr, attributes: [
                .font: mainFont, .foregroundColor: valColor
            ]).draw(at: NSPoint(x: cX, y: mainY))
            let sa = NSAttributedString(string: statStr, attributes: [
                .font: statFont, .foregroundColor: statColor
            ])
            sa.draw(at: NSPoint(x: rightEdge - sa.size().width, y: mainY))

            let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH), xRadius: barR, yRadius: barR)
            NSColor.separatorColor.withAlphaComponent(0.2).setFill(); track.fill()
        }
    }
}

// MARK: - Network Card

final class NetworkCard: NSView {
    struct Col { var label: String; var valueStr: String; var color: NSColor }
    var cols: [Col] = [] { didSet { needsDisplay = true } }

    static let h: CGFloat = Layout.sectionHeadH + Layout.rowHeight

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW

        NSAttributedString(string: "网络", attributes: [
            .font: Typography.section(), .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX, y: bounds.height - Layout.sectionHeadH + 2))

        let rowBottom = bounds.height - Layout.sectionHeadH - Layout.rowHeight
        let barH = Layout.barHeight, mainY = rowBottom + barH + 4 + 4, titleY = mainY + 25 + 3
        let mainFont = Typography.bigValue(), titleFont = Typography.section()

        for (i, col) in cols.prefix(2).enumerated() {
            let va = NSAttributedString(string: col.valueStr, attributes: [.font: mainFont, .foregroundColor: col.color])
            let la = NSAttributedString(string: col.label, attributes: [.font: titleFont, .foregroundColor: NSColor.secondaryLabelColor])
            let valX: CGFloat = i == 0 ? cX : rightEdge - va.size().width
            let lblX: CGFloat = i == 0 ? cX : rightEdge - la.size().width
            va.draw(at: NSPoint(x: valX, y: mainY))
            la.draw(at: NSPoint(x: lblX, y: titleY))
        }
    }
}

// MARK: - Disk Card

final class DiskCard: NSView {
    struct Entry {
        var label: String; var valueStr: String; var percent: Double; var color: NSColor
        var warnAt: Double; var critAt: Double
    }
    var entries: [Entry] = [] {
        didSet { updateBarLayers(); needsDisplay = true }
    }

    private var barLayers: [CALayer] = []
    private var layersReady = false

    static let h: CGFloat = Layout.sectionHeadH + 2 * Layout.rowHeight + Layout.rowGap

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<2 {
            let l = CALayer(); l.cornerRadius = Layout.barRadius; l.masksToBounds = true
            barLayers.append(l); layer?.addSublayer(l)
        }
        layersReady = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); updateBarLayers() }

    private func updateBarLayers() {
        guard layersReady, !entries.isEmpty else { return }
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2
        let barH = Layout.barHeight, headH = Layout.sectionHeadH
        let rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let contentH = bounds.height - headH
        for (i, e) in entries.enumerated() {
            guard i < barLayers.count else { continue }
            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4
            let color: NSColor = e.percent >= 0 && e.percent >= e.critAt ? .systemRed
                               : e.percent >= 0 && e.percent >= e.warnAt ? .systemOrange : e.color
            let fillW = e.percent >= 0 ? max(barH, cW * CGFloat(min(max(e.percent, 0), 1))) : barH
            barLayers[i].frame = CGRect(x: cX, y: barY, width: fillW, height: barH)
            barLayers[i].backgroundColor = color.withAlphaComponent(0.75).cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW
        let barH = Layout.barHeight, barR = Layout.barRadius
        let headH = Layout.sectionHeadH, rowH = Layout.rowHeight, rowGap = Layout.rowGap
        let mainFont = Typography.bigValue(), titleFont = Typography.section(), statFont = Typography.state()

        NSAttributedString(string: "磁盘", attributes: [
            .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))

        for (i, e) in entries.enumerated() {
            let valColor: NSColor = e.percent >= 0 && e.percent >= e.critAt ? .systemRed
                                  : e.percent >= 0 && e.percent >= e.warnAt ? .systemOrange
                                  : e.color
            let statColor: NSColor = e.percent >= 0 && e.percent >= e.critAt ? .systemRed
                                   : e.percent >= 0 && e.percent >= e.warnAt ? .systemOrange
                                   : .systemGreen
            let statStr = e.percent >= 0 && e.percent >= e.critAt ? "紧张"
                        : e.percent >= 0 && e.percent >= e.warnAt ? "偏高" : "正常"

            let contentH = bounds.height - headH
            let rowBottom = contentH - CGFloat(i) * (rowH + rowGap) - rowH
            let barY = rowBottom + 4, mainY = barY + barH + 4, titleY = mainY + 25 + 3

            NSAttributedString(string: e.label, attributes: [
                .font: titleFont, .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: titleY))
            NSAttributedString(string: e.valueStr, attributes: [
                .font: mainFont, .foregroundColor: valColor
            ]).draw(at: NSPoint(x: cX, y: mainY))
            let sa = NSAttributedString(string: statStr, attributes: [
                .font: statFont, .foregroundColor: statColor
            ])
            sa.draw(at: NSPoint(x: rightEdge - sa.size().width, y: mainY))

            let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH), xRadius: barR, yRadius: barR)
            NSColor.separatorColor.withAlphaComponent(0.2).setFill(); track.fill()
        }
    }
}

// MARK: - Fan Control Card

final class FanCard: NSView {
    var curRPM: Double = 0
    var minRPM: Double = 1500
    var maxRPM: Double = 4700
    var isManual: Bool = false
    var pendingChange: Bool = false
    var onSliderChange: ((Double) -> Void)?

    private let slider = NSSlider()

    static let h: CGFloat = 96

    override init(frame: NSRect) {
        super.init(frame: frame)
        slider.minValue = minRPM; slider.maxValue = maxRPM
        slider.doubleValue = minRPM
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(sliderMoved(_:))
        addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError() }

    private let h_val: CGFloat = 28, h_sub: CGFloat = 13, h_sld: CGFloat = 20, h_tick: CGFloat = 11, gap: CGFloat = 5
    private var mainY: CGFloat { FanCard.h - gap - h_val }
    private var subY: CGFloat  { mainY - gap - h_sub }
    private var sldrY: CGFloat { subY - gap - h_sld }
    private var tickY: CGFloat { sldrY - gap - h_tick }

    override func layout() {
        super.layout()
        slider.frame = NSRect(x: Layout.innerPad - 2, y: sldrY,
                              width: bounds.width - Layout.innerPad * 2 + 4, height: h_sld)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let w = bounds.width, cX = Layout.innerPad, cW = w - Layout.innerPad * 2, rightEdge = cX + cW
        let rpmColor: NSColor = isManual ? .systemOrange : .systemBlue

        let tickFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let tc = NSColor.tertiaryLabelColor
        let minA = NSAttributedString(string: String(format: "%.0f", minRPM), attributes: [.font: tickFont, .foregroundColor: tc])
        let maxA = NSAttributedString(string: String(format: "%.0f", maxRPM), attributes: [.font: tickFont, .foregroundColor: tc])
        minA.draw(at: NSPoint(x: cX, y: tickY))
        maxA.draw(at: NSPoint(x: rightEdge - maxA.size().width, y: tickY))

        let subFont = NSFont.systemFont(ofSize: 10), subColor = NSColor.secondaryLabelColor
        NSAttributedString(string: "当前转速", attributes: [.font: subFont, .foregroundColor: subColor])
            .draw(at: NSPoint(x: cX, y: subY))
        if isManual {
            let ta = NSAttributedString(string: String(format: "目标 %.0f rpm", slider.doubleValue),
                attributes: [.font: subFont, .foregroundColor: rpmColor.withAlphaComponent(0.8)])
            ta.draw(at: NSPoint(x: rightEdge - ta.size().width, y: subY))
        }

        let rpmA = NSAttributedString(string: String(format: "%.0f", curRPM),
            attributes: [.font: Typography.bigValue(), .foregroundColor: rpmColor])
        rpmA.draw(at: NSPoint(x: cX, y: mainY))
        NSAttributedString(string: "rpm", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
            .draw(at: NSPoint(x: cX + rpmA.size().width + 4, y: mainY + 4))
        let modeA = NSAttributedString(string: isManual ? "手动" : "自动",
            attributes: [.font: Typography.state(), .foregroundColor: rpmColor])
        modeA.draw(at: NSPoint(x: rightEdge - modeA.size().width, y: mainY))
    }

    func update(cur: Double, min: Double, max: Double, target: Double, manual: Bool) {
        guard !pendingChange else {
            curRPM = cur; if manual { pendingChange = false }; needsDisplay = true; return
        }
        curRPM = cur; minRPM = min; maxRPM = max; isManual = manual
        slider.minValue = min; slider.maxValue = max
        if !isManual { setSliderSilently(min) }
        needsDisplay = true
    }

    private func setSliderSilently(_ v: Double) {
        slider.target = nil; slider.action = nil
        slider.doubleValue = v
        slider.target = self; slider.action = #selector(sliderMoved(_:))
    }

    @objc private func sliderMoved(_ s: NSSlider) {
        pendingChange = true
        onSliderChange?(s.doubleValue)
    }
}

// MARK: - Charge Chart

final class ChargeChartView: NSView {
    struct Sample { var watts: Double; var mode: Int }
    private var samples: [Sample] = []
    var powerMode: Int = 0
    private let windowSize = 60
    private var lastScale: Double = 0

    private var curveLayers: [CAShapeLayer] = []
    private var fillMask = CAShapeLayer()
    private var fillGrad: CAGradientLayer?

    func push(watts: Double) {
        samples.append(Sample(watts: watts, mode: powerMode))
        if samples.count > windowSize { samples.removeFirst() }
        let maxVal = max((samples.map(\.watts).max() ?? 1.0), 5.0)
        let scale = niceMax(maxVal)
        if abs(scale - lastScale) > 1 { lastScale = scale; needsDisplay = true }
        updateCurveLayers()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateCurveLayers()
    }

    private func ensureLayers(for count: Int) {
        while curveLayers.count < count {
            let l = CAShapeLayer()
            l.fillColor = nil; l.lineWidth = 1.5
            l.lineCap = .round; l.lineJoin = .round
            layer?.addSublayer(l)
            curveLayers.append(l)
        }
        while curveLayers.count > count {
            curveLayers.removeLast().removeFromSuperlayer()
        }
        if fillGrad == nil {
            let g = CAGradientLayer()
            g.mask = fillMask
            g.startPoint = CGPoint(x: 0.5, y: 1.0)
            g.endPoint   = CGPoint(x: 0.5, y: 0.0)
            layer?.addSublayer(g)
            fillGrad = g
        }
    }

    private func updateCurveLayers() {
        guard samples.count >= 2 else { curveLayers.forEach { $0.path = nil }; fillMask.path = nil; return }
        let leftPad: CGFloat = 22, rightPad: CGFloat = 4, topPad: CGFloat = 10, botPad: CGFloat = 20
        let plotW = bounds.width - leftPad - rightPad, plotH = bounds.height - topPad - botPad
        let originX = leftPad, originY = botPad
        let scale = lastScale > 0 ? lastScale : niceMax(max((samples.map(\.watts).max() ?? 1.0), 5.0))
        lastScale = scale

        let n = samples.count
        let pts: [CGPoint] = samples.enumerated().map { i, s in
            let slotFromRight = n - 1 - i
            let x = originX + plotW - CGFloat(slotFromRight) / CGFloat(windowSize - 1) * plotW
            let y = originY + CGFloat(min(s.watts, scale) / scale) * plotH
            return CGPoint(x: x, y: y)
        }

        func smoothPath(_ pts: [CGPoint]) -> CGMutablePath {
            let p = CGMutablePath(); p.move(to: pts[0])
            for i in 1..<pts.count {
                let p0 = pts[max(i-2,0)], p1 = pts[i-1], p2 = pts[i], p3 = pts[min(i+1, pts.count-1)]
                p.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            }
            return p
        }

        func modeSegments() -> [(Int, Int)] {
            var segs: [(Int, Int)] = []; var start = 0
            for i in 1..<samples.count {
                if samples[i].mode != samples[start].mode { segs.append((start, i-1)); start = i }
            }
            segs.append((start, samples.count - 1)); return segs
        }

        func modeColor(_ m: Int) -> NSColor {
            switch m { case 1: .systemGreen; case 2: .systemBlue; default: .systemYellow }
        }

        let segs = modeSegments()
        ensureLayers(for: segs.count)

        for (idx, (lo, hi)) in segs.enumerated() {
            let segPts = Array(pts[lo...hi])
            curveLayers[idx].path = hi > lo ? smoothPath(segPts) : nil
            curveLayers[idx].strokeColor = modeColor(samples[lo].mode).withAlphaComponent(0.9).cgColor
        }

        let fillPath = smoothPath(pts)
        fillPath.addLine(to: CGPoint(x: pts.last!.x, y: originY))
        fillPath.addLine(to: CGPoint(x: pts.first!.x, y: originY))
        fillPath.closeSubpath()
        fillMask.path = fillPath
        fillMask.fillColor = NSColor.black.cgColor
        if let g = fillGrad {
            let mc = modeColor(samples.last?.mode ?? 0)
            g.colors = [mc.withAlphaComponent(0.28).cgColor, mc.withAlphaComponent(0.03).cgColor]
            g.frame = bounds
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        guard samples.count >= 2 else {
            NSAttributedString(string: "积累数据中…", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: bounds.width / 2 - 30, y: bounds.height / 2 - 6))
            return
        }
        let leftPad: CGFloat = 22, rightPad: CGFloat = 4, topPad: CGFloat = 10, botPad: CGFloat = 20
        let plotW = bounds.width - leftPad - rightPad, plotH = bounds.height - topPad - botPad
        let originX = leftPad, originY = botPad
        let scale = lastScale

        let gridColor = NSColor.separatorColor.withAlphaComponent(0.25)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for step in yTicks(scale: scale) {
            let y = originY + CGFloat(step / scale) * plotH
            let path = NSBezierPath(); path.move(to: NSPoint(x: originX, y: y)); path.line(to: NSPoint(x: originX + plotW, y: y))
            path.lineWidth = 0.5; gridColor.setStroke(); path.stroke()
            let lbl = NSAttributedString(string: "\(Int(step))", attributes: labelAttrs)
            lbl.draw(at: NSPoint(x: originX - lbl.size().width - 3, y: y - lbl.size().height / 2))
        }

        if let last = samples.last, last.watts > 0 {
            let accent = modeColor(last.mode)
            let curAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: accent]
            let lbl = NSAttributedString(string: String(format: "%.1fW", last.watts), attributes: curAttrs)
            lbl.draw(at: NSPoint(x: originX + plotW - lbl.size().width, y: originY + plotH - lbl.size().height))
        }
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.quaternaryLabelColor]
        NSAttributedString(string: samples.count >= windowSize ? "60s" : "\(samples.count)s", attributes: timeAttrs)
            .draw(at: NSPoint(x: originX + plotW - 24, y: botPad - 14))
    }

    private func modeColor(_ m: Int) -> NSColor {
        switch m { case 1: .systemGreen; case 2: .systemBlue; default: .systemYellow }
    }

    private func niceMax(_ v: Double) -> Double {
        if v <= 0 { return 10 }
        return [5.0, 10, 15, 20, 30, 40, 50, 60, 80, 100, 120, 150, 200].first { $0 >= v * 1.1 } ?? (ceil(v * 1.1 / 10) * 10)
    }

    private func yTicks(scale: Double) -> [Double] {
        (0...4).map { Double($0) / 4.0 * scale }
    }
}

// MARK: - Battery Card

final class BatteryCard: NSView {
    var percent: Double = 0
    var timeLine: String = "--"
    var powerMode: Int = 0
    var isLowPower: Bool = false

    private let chart = ChargeChartView(frame: .zero)
    private let barFillLayer = CALayer()

    static let h: CGFloat = 244

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        barFillLayer.cornerRadius = 4
        barFillLayer.masksToBounds = true
        layer?.addSublayer(barFillLayer)
        addSubview(chart)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let topPad: CGFloat = 20, rowH = Layout.rowHeight
        let dataTop = bounds.height - topPad - rowH
        let chartH = dataTop - 12
        chart.frame = NSRect(x: 8, y: 10, width: bounds.width - 16, height: max(chartH - 10, 0))
        updateBarLayer()
    }

    func pushSample(watts: Double) {
        chart.powerMode = powerMode
        chart.push(watts: watts)
    }

    private func updateBarLayer() {
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2
        let barH: CGFloat = 12, inset: CGFloat = 2
        let contentH = bounds.height - 20
        let rowBottom = contentH - Layout.rowHeight
        let barY = rowBottom + 4
        let barW = cW - 4
        let fillW = max(barH, (barW - inset * 2) * CGFloat(min(max(percent, 0), 1)))
        barFillLayer.frame = NSRect(x: cX + inset, y: barY + inset, width: fillW, height: barH - inset * 2)
        barFillLayer.backgroundColor = barColor().cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        updateBarLayer()
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW
        let contentH = bounds.height - 20
        let rowBottom = contentH - Layout.rowHeight

        let subText = (powerMode == 2) ? "" : timeLine
        let infoH: CGFloat = subText.isEmpty ? 0 : 14

        let barH: CGFloat = 12, barR = barH / 2
        let barY = rowBottom + 4, barW = cW - 4
        let rc = NSRect(x: cX, y: barY, width: barW, height: barH)
        barColor().withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: rc, xRadius: barR, yRadius: barR).lineWidth = 1.5
        NSBezierPath(roundedRect: rc, xRadius: barR, yRadius: barR).stroke()
        let nip = NSRect(x: cX + barW + 1, y: barY + 3, width: 3, height: 6)
        barColor().withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: nip, xRadius: 1, yRadius: 1).fill()

        if !subText.isEmpty {
            NSAttributedString(string: subText, attributes: [
                .font: Typography.label(), .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: barY + barH + 4))
        }

        let mainY = barY + barH + infoH + 4
        NSAttributedString(string: String(format: "%.0f%%", percent * 100), attributes: [
            .font: Typography.hugeValue(), .foregroundColor: barColor()
        ]).draw(at: NSPoint(x: cX, y: mainY))

        let (statStr, statColor): (String, NSColor) = {
            switch powerMode {
            case 0: return isLowPower
                ? ("节电", NSColor(red: 247/255, green: 206/255, blue: 70/255, alpha: 1))
                : ("放电中", .systemYellow)
            case 1: return ("充电中", .systemGreen)
            default: return ("满电供电", .systemBlue)
            }
        }()
        let sa = NSAttributedString(string: statStr, attributes: [.font: Typography.state(), .foregroundColor: statColor])
        sa.draw(at: NSPoint(x: rightEdge - sa.size().width, y: mainY))

        if powerMode == 1, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)) {
            let bsz = bolt.size
            let bx = rightEdge - sa.size().width - bsz.width - 3
            let by = mainY + (sa.size().height - bsz.height) / 2 + 2
            let tinted = NSImage(size: bsz, flipped: false) { r in statColor.setFill(); r.fill(); bolt.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0); return true }
            tinted.draw(in: NSRect(x: bx, y: by, width: bsz.width, height: bsz.height))
        }
    }

    private func barColor() -> NSColor {
        switch powerMode {
        case 1: return .systemGreen
        case 2: return .systemBlue
        default:
            if percent < 0.2 { return .systemRed }
            if isLowPower { return NSColor(red: 247/255, green: 206/255, blue: 70/255, alpha: 1) }
            return .systemGreen
        }
    }
}

// MARK: - Efficiency Card

final class EfficiencyCard: NSView {
    var avgWatts: Double = 0 { didSet { needsDisplay = true } }
    var timeToEmpty: Int = -1 { didSet { needsDisplay = true } }
    var isOnBattery: Bool = false { didSet { needsDisplay = true } }

    static let h: CGFloat = 68

    private var grade: Int {
        let wGrade = avgWatts < 10 ? 0 : avgWatts < 15 ? 1 : 2
        if !isOnBattery { return wGrade }
        let tGrade: Int
        if timeToEmpty <= 0 || timeToEmpty >= 240 { tGrade = 0 }
        else if timeToEmpty >= 120 { tGrade = 1 }
        else { tGrade = 2 }
        return max(wGrade, tGrade)
    }

    private var gradeColor: NSColor {
        switch grade { case 0: .systemGreen; case 1: .systemOrange; default: .systemRed }
    }
    private var gradeLabel: String {
        switch grade { case 0: "高效"; case 1: "中等"; default: "高耗" }
    }

    override func draw(_ dirty: NSRect) {
        let cX = Layout.innerPad, cW = bounds.width - Layout.innerPad * 2, rightEdge = cX + cW, color = gradeColor

        let barH: CGFloat = 6, barR = barH / 2, barY: CGFloat = barH / 2 + 4
        let track = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: cW, height: barH), xRadius: barR, yRadius: barR)
        NSColor.separatorColor.withAlphaComponent(0.2).setFill(); track.fill()
        if avgWatts > 0 {
            let fillW = max(barH, cW * CGFloat(min(avgWatts / 50, 1)))
            let fill = NSBezierPath(roundedRect: NSRect(x: cX, y: barY, width: fillW, height: barH), xRadius: barR, yRadius: barR)
            color.withAlphaComponent(0.75).setFill(); fill.fill()
        }

        let subFont = Typography.label(), subColor = NSColor.secondaryLabelColor, subY = barY + barH + 6
        NSAttributedString(string: "均值功耗", attributes: [.font: subFont, .foregroundColor: subColor])
            .draw(at: NSPoint(x: cX, y: subY))
        let sra = NSAttributedString(string: "能效评级", attributes: [.font: subFont, .foregroundColor: subColor])
        sra.draw(at: NSPoint(x: rightEdge - sra.size().width, y: subY))

        let mainY = subY + 14 + 4
        let wStr = avgWatts > 0 ? String(format: "%.1fW", avgWatts) : "--"
        NSAttributedString(string: wStr, attributes: [.font: Typography.bigValue(), .foregroundColor: color])
            .draw(at: NSPoint(x: cX, y: mainY))

        let dotSz: CGFloat = 8
        let ga = NSAttributedString(string: gradeLabel, attributes: [.font: Typography.state(), .foregroundColor: color])
        let gsz = ga.size()
        let gradeTextX = rightEdge - gsz.width
        let dotX = gradeTextX - dotSz - 5, dotY = mainY + (gsz.height - dotSz) / 2 + 1
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotSz, height: dotSz)).fill()
        ga.draw(at: NSPoint(x: gradeTextX, y: mainY))
    }
}
