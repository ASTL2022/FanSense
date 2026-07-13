import Cocoa

// MARK: - Charge History Chart

final class ChargeChartView: NSView {
    private struct Sample {
        var watts: Double
        var mode: Int   // 0=discharging(yellow), 1=charging(green), 2=full(blue)
    }
    private var samples: [Sample] = []
    var powerMode: Int = 0   // current stable mode

    // Fixed 1-minute window: 60 slots at 1 sample/sec.
    private let windowSize = 60

    func push(watts: Double) {
        samples.append(Sample(watts: watts, mode: powerMode))
        if samples.count > windowSize { samples.removeFirst() }
        display()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard samples.count >= 2 else {
            NSAttributedString(string: "积累数据中…", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]).draw(at: NSPoint(x: bounds.width / 2 - 30,
                                 y: bounds.height / 2 - 6))
            return
        }

        let leftPad: CGFloat  = 22    // Y 轴标签空间
        let rightPad: CGFloat = 4
        let topPad: CGFloat   = 10
        let botPad: CGFloat   = 20

        let plotW = bounds.width - leftPad - rightPad
        let plotH = bounds.height - topPad - botPad
        let originX = leftPad
        let originY = botPad

        let maxVal = max((samples.map(\.watts).max() ?? 1.0), 5.0)
        let scale  = niceMax(maxVal)

        // --- grid + y labels (标签在 plot 左侧外部) ---
        let gridColor = NSColor.separatorColor.withAlphaComponent(0.25)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let ticks = yTicks(scale: scale)
        for step in ticks {
            let y = originY + CGFloat(step / scale) * plotH
            let path = NSBezierPath()
            path.move(to: NSPoint(x: originX, y: y))
            path.line(to: NSPoint(x: originX + plotW, y: y))
            path.lineWidth = 0.5
            gridColor.setStroke()
            path.stroke()
            let lbl = NSAttributedString(string: "\(Int(step))", attributes: labelAttrs)
            let sz  = lbl.size()
            lbl.draw(at: NSPoint(x: originX - sz.width - 3, y: y - sz.height / 2))
        }

        // X-axis is always 60 s wide; latest sample is at right edge.
        let n = samples.count
        let pts: [NSPoint] = samples.enumerated().map { i, s in
            let slotFromRight = n - 1 - i          // 0 = newest … n-1 = oldest
            let x = originX + plotW - CGFloat(slotFromRight) / CGFloat(windowSize - 1) * plotW
            let y = originY + CGFloat(min(s.watts, scale) / scale) * plotH
            return NSPoint(x: x, y: y)
        }

        // --- fill + stroke in color segments ---
        func modeColor(_ m: Int) -> NSColor {
            switch m {
            case 1:  return .systemGreen
            case 2:  return .systemBlue
            default: return .systemYellow
            }
        }

        let fullCurve = smoothPath(pts)

        let clipPath = fullCurve.copy() as! NSBezierPath
        clipPath.line(to: NSPoint(x: pts.last!.x,  y: originY))
        clipPath.line(to: NSPoint(x: pts.first!.x, y: originY))
        clipPath.close()

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            clipPath.addClip()

            var segStart = 0
            while segStart < n {
                let segMode = samples[segStart].mode
                var segEnd = segStart
                while segEnd + 1 < n && samples[segEnd + 1].mode == segMode {
                    segEnd += 1
                }
                if segEnd >= segStart {
                    let accent = modeColor(segMode)
                    let x0 = pts[segStart].x
                    let x1 = segEnd + 1 < n ? pts[segEnd + 1].x : pts[segEnd].x
                    let fillRect = CGRect(x: x0, y: originY, width: max(x1 - x0, 1), height: plotH)
                    let colors = [accent.withAlphaComponent(0.28).cgColor,
                                  accent.withAlphaComponent(0.03).cgColor]
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
                }
                segStart = segEnd + 1
            }
            ctx.restoreGState()
        }

        // --- stroke each segment in its color ---
        var segStart = 0
        while segStart < n {
            let segMode = samples[segStart].mode
            var segEnd = segStart
            while segEnd + 1 < n && samples[segEnd + 1].mode == segMode {
                segEnd += 1
            }
            if segEnd > segStart {
                let segPts = Array(pts[segStart...segEnd])
                let accent = modeColor(segMode)
                let curve = smoothPath(segPts)
                curve.lineWidth = 1.5
                curve.lineCapStyle  = .round
                curve.lineJoinStyle = .round
                accent.withAlphaComponent(0.9).setStroke()
                curve.stroke()
            }
            segStart = segEnd + 1
        }

        // Cross-fade overlay at every mode transition.
        for i in 1..<n where samples[i].mode != samples[i - 1].mode {
            let blendL = max(0, i - 2)
            let blendR = min(n - 1, i + 1)
            guard blendR > blendL else { continue }
            let fromColor = modeColor(samples[i - 1].mode)
            let toColor   = modeColor(samples[i].mode)
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

        // current value label — top-right corner badge
        if let last = samples.last, last.watts > 0 {
            let accent = modeColor(last.mode)
            let curAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: accent
            ]
            let lbl = NSAttributedString(string: String(format: "%.1fW", last.watts), attributes: curAttrs)
            let sz  = lbl.size()
            lbl.draw(at: NSPoint(x: originX + plotW - sz.width,
                                 y: originY + plotH - sz.height))
        }

        // x-axis time label
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.quaternaryLabelColor
        ]
        let timeStr = n >= windowSize ? "60s" : "\(n)s"
        NSAttributedString(string: timeStr, attributes: timeAttrs)
            .draw(at: NSPoint(x: originX + plotW - 24, y: botPad - 14))
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
        if v <= 0 { return 10 }
        let steps: [Double] = [5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 120, 150, 200]
        return steps.first { $0 >= v * 1.1 } ?? (ceil(v * 1.1 / 10) * 10)
    }

    private func yTicks(scale: Double) -> [Double] {
        let count = 4
        return (0...count).map { Double($0) / Double(count) * scale }
    }
}

