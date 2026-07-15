import Cocoa

// MARK: - Fan View (RPM readout + slider + 60s history chart)

final class FanView: NSView {
    static let h: CGFloat = 322   // 左列与右列总高对齐: 722 - 10 - 270 - 94 - 10 - 16(卡片内边距) = 322

    var curRPM: Double = 0
    var minRPM: Double = 1500
    var maxRPM: Double = 4700
    var isManual: Bool = false
    var sectionTitle: String = "风扇"
    var onSliderChange: ((Double) -> Void)?

    // true from first sliderMoved until debounce fires and SMC write completes
    var pendingChange = false

    private let slider = NSSlider()
    private struct Sample {
        var rpm: Double
        var manual: Bool
    }
    private var samples: [Sample] = []
    private let windowSize = 60

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        slider.minValue     = minRPM
        slider.maxValue     = maxRPM
        slider.doubleValue  = minRPM   // 默认最左 = 自动
        slider.isContinuous = true
        slider.target       = self
        slider.action       = #selector(sliderMoved(_:))
        addSubview(slider)
    }

    // ── 布局常量（自上而下）──
    private let headH:  CGFloat = 16   // 区段标题
    private let h_val:  CGFloat = 28   // 主数值行高（22pt 字体）
    private let h_sub:  CGFloat = 13   // 副标签行高
    private let h_sld:  CGFloat = 20   // 滑块高
    private let h_tick: CGFloat = 11   // 刻度行高
    private let gap:    CGFloat = 5    // 行间距

    private var mainY:  CGFloat { bounds.height - headH - gap - h_val }
    private var subY:   CGFloat { mainY - gap - h_sub }
    private var tickY:  CGFloat { 6 }
    private var sldrY:  CGFloat { tickY + h_tick + gap }
    private var chartTop:    CGFloat { subY - gap - 4 }
    private var chartBottom: CGFloat { sldrY + h_sld + 4 }

    override func layout() {
        super.layout()
        slider.frame = NSRect(x: IP - 2, y: sldrY,
                              width: bounds.width - IP * 2 + 4, height: h_sld)
    }

    // MARK: - Data

    func update(cur: Double, min: Double, max: Double, target: Double, manual: Bool) {
        // While user has a pending slider command, don't let SMC state overwrite local UI.
        // Clear pendingChange only when SMC confirms manual mode (meaning the set command landed).
        guard !pendingChange else {
            curRPM = cur
            if manual { pendingChange = false }   // set command confirmed
            needsDisplay = true
            return
        }

        curRPM   = cur
        minRPM   = min
        maxRPM   = max
        isManual = manual

        slider.minValue = min
        slider.maxValue = max

        if !isManual {
            setSliderSilently(min)
        }

        needsDisplay = true
    }

    func push(rpm: Double) {
        samples.append(Sample(rpm: rpm, manual: isManual))
        if samples.count > windowSize { samples.removeFirst() }
        needsDisplay = true
    }

    private func setSliderSilently(_ v: Double) {
        slider.target = nil
        slider.action = nil
        slider.doubleValue = v
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
    }

    func setSliderValue(_ v: Double) {
        setSliderSilently(v)
    }

    @objc private func sliderMoved(_ s: NSSlider) {
        pendingChange = true
        onSliderChange?(s.doubleValue)
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let cX = IP
        let cW = bounds.width - IP * 2
        let rightEdge = cX + cW
        let accent: NSColor = isManual ? .systemOrange : .systemBlue

        // ── 区段标题 ──
        if !sectionTitle.isEmpty {
            NSAttributedString(string: sectionTitle, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: cX, y: bounds.height - headH + 2))
        }

        // ── 主数值行 ──
        let rpmAttr = NSAttributedString(string: String(format: "%.0f", curRPM), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: accent
        ])
        rpmAttr.draw(at: NSPoint(x: cX, y: mainY))
        NSAttributedString(string: "rpm", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX + rpmAttr.size().width + 4, y: mainY + 4))

        let modeAttr = NSAttributedString(string: isManual ? "手动" : "自动", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: accent
        ])
        let msz = modeAttr.size()
        let modeTextX = rightEdge - msz.width
        let dotSize: CGFloat = 8
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: modeTextX - dotSize - 5,
                                    y: mainY + (msz.height - dotSize) / 2 + 1,
                                    width: dotSize, height: dotSize)).fill()
        modeAttr.draw(at: NSPoint(x: modeTextX, y: mainY))

        // ── 副标签行 ──
        let subFont  = NSFont.systemFont(ofSize: 10)
        let subColor = NSColor.secondaryLabelColor
        NSAttributedString(string: "当前转速", attributes: [
            .font: subFont, .foregroundColor: subColor
        ]).draw(at: NSPoint(x: cX, y: subY))

        if isManual {
            let tAttr = NSAttributedString(
                string: String(format: "目标 %.0f rpm", slider.doubleValue),
                attributes: [.font: subFont, .foregroundColor: accent.withAlphaComponent(0.8)])
            tAttr.draw(at: NSPoint(x: rightEdge - tAttr.size().width, y: subY))
        }

        // ── min/max 刻度 ──
        let tickFont  = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let tickColor = NSColor.tertiaryLabelColor
        let minAttr   = NSAttributedString(string: String(format: "%.0f", minRPM),
                                           attributes: [.font: tickFont, .foregroundColor: tickColor])
        let maxAttr   = NSAttributedString(string: String(format: "%.0f", maxRPM),
                                           attributes: [.font: tickFont, .foregroundColor: tickColor])
        minAttr.draw(at: NSPoint(x: cX, y: tickY))
        maxAttr.draw(at: NSPoint(x: rightEdge - maxAttr.size().width, y: tickY))

        // ── 60s 历史曲线 ──
        drawChart(cX: cX, cW: cW, accent: accent)
    }

    private func drawChart(cX: CGFloat, cW: CGFloat, accent: NSColor) {
        guard samples.count >= 2 else {
            NSAttributedString(string: "积累数据中…", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: bounds.width / 2 - 30,
                                 y: (chartTop + chartBottom) / 2 - 6))
            return
        }

        let leftPad: CGFloat  = 30
        let rightPad: CGFloat = 4
        let topPad: CGFloat   = 10
        let botPad: CGFloat   = 16

        let plotW = cW - leftPad - rightPad
        let originX = cX + leftPad
        let originY = chartBottom + botPad
        let plotH = chartTop - topPad - originY

        let scale = max(niceMax(max(samples.map(\.rpm).max() ?? 0, 1500)), 1)

        // grid + y labels
        let gridColor = NSColor.separatorColor.withAlphaComponent(0.25)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let tickCount = 4
        for t in 0...tickCount {
            let step = Double(t) / Double(tickCount) * scale
            let y = originY + CGFloat(step / scale) * plotH
            let path = NSBezierPath()
            path.move(to: NSPoint(x: originX, y: y))
            path.line(to: NSPoint(x: originX + plotW, y: y))
            path.lineWidth = 0.5
            gridColor.setStroke()
            path.stroke()
            let lbl = NSAttributedString(string: rpmLabel(step), attributes: labelAttrs)
            let sz  = lbl.size()
            lbl.draw(at: NSPoint(x: originX - sz.width - 3, y: y - sz.height / 2))
        }

        let n = samples.count
        let pts: [NSPoint] = samples.enumerated().map { i, s in
            let slotFromRight = n - 1 - i
            let x = originX + plotW - CGFloat(slotFromRight) / CGFloat(windowSize - 1) * plotW
            let y = originY + CGFloat(min(s.rpm, scale) / scale) * plotH
            return NSPoint(x: x, y: y)
        }

        func modeColor(_ manual: Bool) -> NSColor {
            manual ? .systemOrange : .systemBlue
        }

        let fullCurve = smoothPath(pts)

        // --- fill in color segments ---
        if let ctx = NSGraphicsContext.current?.cgContext {
            let clipPath = fullCurve.copy() as! NSBezierPath
            clipPath.line(to: NSPoint(x: pts.last!.x,  y: originY))
            clipPath.line(to: NSPoint(x: pts.first!.x, y: originY))
            clipPath.close()
            ctx.saveGState()
            clipPath.addClip()

            var segStart = 0
            while segStart < n {
                let segMode = samples[segStart].manual
                var segEnd = segStart
                while segEnd + 1 < n && samples[segEnd + 1].manual == segMode {
                    segEnd += 1
                }
                let seg = modeColor(segMode)
                let x0 = pts[segStart].x
                let x1 = segEnd + 1 < n ? pts[segEnd + 1].x : pts[segEnd].x
                let fillRect = CGRect(x: x0, y: originY, width: max(x1 - x0, 1), height: plotH)
                let colors = [seg.withAlphaComponent(0.28).cgColor,
                              seg.withAlphaComponent(0.03).cgColor]
                let locs: [CGFloat] = [1.0, 0.0]
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: locs) {
                    ctx.saveGState()
                    ctx.clip(to: fillRect)
                    ctx.drawLinearGradient(grad,
                        start: CGPoint(x: x0, y: originY + plotH),
                        end:   CGPoint(x: x0, y: originY),
                        options: [])
                    ctx.restoreGState()
                }
                segStart = segEnd + 1
            }
            ctx.restoreGState()
        }

        // --- stroke each segment in its color ---
        var segStart = 0
        while segStart < n {
            let segMode = samples[segStart].manual
            var segEnd = segStart
            while segEnd + 1 < n && samples[segEnd + 1].manual == segMode {
                segEnd += 1
            }
            if segEnd > segStart {
                let segPts = Array(pts[segStart...segEnd])
                let curve = smoothPath(segPts)
                curve.lineWidth = 1.5
                curve.lineCapStyle  = .round
                curve.lineJoinStyle = .round
                modeColor(segMode).withAlphaComponent(0.9).setStroke()
                curve.stroke()
            }
            segStart = segEnd + 1
        }

        // --- cross-fade overlay at mode transitions ---
        for i in 1..<n where samples[i].manual != samples[i - 1].manual {
            let blendL = max(0, i - 2)
            let blendR = min(n - 1, i + 1)
            guard blendR > blendL else { continue }
            let fromColor = modeColor(samples[i - 1].manual)
            let toColor   = modeColor(samples[i].manual)
            let bPts = Array(pts[blendL...blendR])
            let steps = max(6, bPts.count * 4)
            for s in 0..<steps {
                let t0 = Double(s)     / Double(steps)
                let t1 = Double(s + 1) / Double(steps)
                let tm = (t0 + t1) / 2
                let p0 = interpolate(bPts, t: t0)
                let p1 = interpolate(bPts, t: t1)
                let c  = fromColor.blended(withFraction: CGFloat(tm), of: toColor) ?? fromColor
                let seg = NSBezierPath()
                seg.move(to: p0)
                seg.line(to: p1)
                seg.lineWidth = 2.0
                seg.lineCapStyle = .round
                c.withAlphaComponent(0.9).setStroke()
                seg.stroke()
            }
        }

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.quaternaryLabelColor
        ]
        let timeStr = n >= windowSize ? "60s" : "\(n)s"
        NSAttributedString(string: timeStr, attributes: timeAttrs)
            .draw(at: NSPoint(x: originX + plotW - 24, y: originY - 14))
    }

    private func rpmLabel(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(format: "%.0f", v)
    }

    private func interpolate(_ pts: [NSPoint], t: Double) -> NSPoint {
        guard pts.count > 1 else { return pts[0] }
        let scaled = t * Double(pts.count - 1)
        let lo = min(Int(scaled), pts.count - 2)
        let frac = scaled - Double(lo)
        let a = pts[lo], b = pts[lo + 1]
        return NSPoint(x: a.x + CGFloat(frac) * (b.x - a.x),
                       y: a.y + CGFloat(frac) * (b.y - a.y))
    }

    private func smoothPath(_ pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: pts[0])
        guard pts.count > 1 else { return path }
        for i in 1..<pts.count {
            let p0 = pts[max(i - 2, 0)]
            let p1 = pts[i - 1]
            let p2 = pts[i]
            let p3 = pts[min(i + 1, pts.count - 1)]
            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6,
                              y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6,
                              y: p2.y - (p3.y - p1.y) / 6)
            path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    private func niceMax(_ v: Double) -> Double {
        if v <= 0 { return 2000 }
        let steps: [Double] = [1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 6000]
        return steps.first { $0 >= v * 1.1 } ?? (ceil(v * 1.1 / 500) * 500)
    }
}
