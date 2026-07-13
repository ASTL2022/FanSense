import Cocoa

// MARK: - Fan Slider View

final class FanSliderView: NSView {
    var curRPM: Double = 0
    var minRPM: Double = 1500
    var maxRPM: Double = 4700
    var isManual: Bool = false
    var onSliderChange: ((Double) -> Void)?

    private let slider = NSSlider()

    static let h: CGFloat = 96

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

    private let h_val:  CGFloat = 28   // 主数值行高（22pt 字体）
    private let h_sub:  CGFloat = 13   // 副标签行高
    private let h_sld:  CGFloat = 20   // 滑块高
    private let h_tick: CGFloat = 11   // 刻度行高
    private let gap:    CGFloat = 5    // 行间距

    private var mainY:  CGFloat { FanSliderView.h - gap - h_val }
    private var subY:   CGFloat { mainY - gap - h_sub }
    private var sldrY:  CGFloat { subY - gap - h_sld }
    private var tickY:  CGFloat { sldrY - gap - h_tick }

    override func layout() {
        super.layout()
        slider.frame = NSRect(x: IP - 2, y: sldrY,
                              width: bounds.width - IP * 2 + 4, height: h_sld)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let w = bounds.width
        let cX = IP
        let cW = w - IP * 2
        let rightEdge = cX + cW
        let rpmColor: NSColor = isManual ? .systemOrange : .systemBlue

        // ── min/max 刻度 ──
        let tickFont  = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let tickColor = NSColor.tertiaryLabelColor
        let minAttr   = NSAttributedString(string: String(format: "%.0f", minRPM),
                                           attributes: [.font: tickFont, .foregroundColor: tickColor])
        let maxAttr   = NSAttributedString(string: String(format: "%.0f", maxRPM),
                                           attributes: [.font: tickFont, .foregroundColor: tickColor])
        minAttr.draw(at: NSPoint(x: cX, y: tickY))
        maxAttr.draw(at: NSPoint(x: rightEdge - maxAttr.size().width, y: tickY))

        // ── 副标签行 ──
        let subFont  = NSFont.systemFont(ofSize: 10)
        let subColor = NSColor.secondaryLabelColor
        NSAttributedString(string: "当前转速", attributes: [
            .font: subFont, .foregroundColor: subColor
        ]).draw(at: NSPoint(x: cX, y: subY))

        if isManual {
            let tAttr = NSAttributedString(
                string: String(format: "目标 %.0f rpm", slider.doubleValue),
                attributes: [.font: subFont, .foregroundColor: rpmColor.withAlphaComponent(0.8)])
            tAttr.draw(at: NSPoint(x: rightEdge - tAttr.size().width, y: subY))
        }

        // ── 主数值行 ──
        let rpmStr  = String(format: "%.0f", curRPM)
        let rpmAttr = NSAttributedString(string: rpmStr, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: rpmColor
        ])
        rpmAttr.draw(at: NSPoint(x: cX, y: mainY))

        NSAttributedString(string: "rpm", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]).draw(at: NSPoint(x: cX + rpmAttr.size().width + 4, y: mainY + 4))

        let modeAttr = NSAttributedString(string: isManual ? "手动" : "自动", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: rpmColor
        ])
        modeAttr.draw(at: NSPoint(x: rightEdge - modeAttr.size().width, y: mainY))
    }

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

    // true from first sliderMoved until debounce fires and SMC write completes
    var pendingChange = false

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

    // NSSlider's mouseDown runs its own tracking loop and never propagates to the
    // parent view, so mouseDown/mouseUp overrides here are unreachable — removed.

    @objc private func sliderMoved(_ s: NSSlider) {
        pendingChange = true
        onSliderChange?(s.doubleValue)
    }
}
