import Cocoa

final class GlassPanel: NSPanel {
    override var isOpaque: Bool { get { false } set {} }
    override var backgroundColor: NSColor! { get { .clear } set {} }
}

// MARK: - Glass Card Factory

final class GlassCardView: NSView {
    var cornerRadius: CGFloat = Layout.cardRadius {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    private let backdrop: CALayer

    override init(frame: NSRect) {
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            backdrop = cls.init()
        } else {
            backdrop = CALayer()
        }
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(backdrop)
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        CATransaction.commit()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        backdrop.frame = bounds
    }

    func applyGlass(blurRadius: Double = 28, tintAlpha: Double = 0.10) {
        guard let filterClass = NSClassFromString("CAFilter") else { return }
        var filters: [AnyObject] = []

        if let blur = makeFilter(cls: filterClass, type: "gaussianBlur") {
            blur.setValue(blurRadius, forKey: "inputRadius")
            blur.setValue("normalizedEdges", forKey: "inputNormalizeEdgesMode")
            blur.setValue(true, forKey: "inputNormalizeEdgesTransparent")
            filters.append(blur)
        }

        if let face = makeFilter(cls: filterClass, type: "glassFace") {
            let isDark = effectiveAppearance.name == .darkAqua
                      || effectiveAppearance.name == .vibrantDark
            face.setValue(isDark ? tintAlpha * 0.3 : tintAlpha, forKey: "inputFaceOpacity")
            face.setValue(1.0, forKey: "inputFaceColorMatrixSaturation")
            face.setValue(1.0, forKey: "inputFaceColorMatrixWhite")
            face.setValue(0.0, forKey: "inputFaceColorMatrixBlack")
            filters.append(face)
        }

        backdrop.backgroundFilters = filters
    }

    func refreshGlassTint() {
        guard let filters = backdrop.backgroundFilters as? [NSObject] else { return }

        let isDark = effectiveAppearance.name == .darkAqua
                  || effectiveAppearance.name == .vibrantDark

        for filter in filters {
            if let type = filter.value(forKey: "type") as? String, type == "glassFace" {
                filter.setValue(isDark ? 0.03 : 0.10, forKey: "inputFaceOpacity")
            }
        }
    }

    private func makeFilter(cls: AnyClass, type: String) -> NSObject? {
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel) else { return nil }
        typealias F = @convention(c) (AnyClass, Selector, AnyObject) -> AnyObject
        let m = class_getClassMethod(cls, sel)!
        let imp = method_getImplementation(m)
        return unsafeBitCast(imp, to: F.self)(cls, sel, type as AnyObject) as? NSObject
    }
}

// MARK: - Card Factory

func makeGlassContainer(cardRect: NSRect) -> GlassCardView {
    let g = GlassCardView(frame: cardRect)
    g.applyGlass()
    return g
}
