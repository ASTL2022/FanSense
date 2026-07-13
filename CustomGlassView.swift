import Cocoa

final class CustomGlassView: NSView {
    var cornerRadius: CGFloat = 14 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var effectIsInteractive: Bool = false

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

    func setupGlass(config: GlassConfig) {
        guard let filterClass = NSClassFromString("CAFilter") else { return }
        var filters: [AnyObject] = []

        if let blur = makeFilter(cls: filterClass, type: "gaussianBlur") {
            blur.setValue(config.blurRadius, forKey: "inputRadius")
            blur.setValue("normalizedEdges", forKey: "inputNormalizeEdgesMode")
            blur.setValue(true, forKey: "inputNormalizeEdgesTransparent")
            filters.append(blur)
        }

        if let face = makeFilter(cls: filterClass, type: "glassFace") {
            let isDark = effectiveAppearance.name == .darkAqua
                      || effectiveAppearance.name == .vibrantDark
            face.setValue(isDark ? config.tintAlpha * 0.3 : config.tintAlpha, forKey: "inputFaceOpacity")
            face.setValue(1.0, forKey: "inputFaceColorMatrixSaturation")
            face.setValue(1.0, forKey: "inputFaceColorMatrixWhite")
            face.setValue(0.0, forKey: "inputFaceColorMatrixBlack")
            filters.append(face)
        }

        backdrop.backgroundFilters = filters
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

struct GlassConfig {
    var blurRadius: Double = 28
    var tintAlpha: Double = 0.10
}
