import Cocoa

func makeCard(cornerRadius: CGFloat) -> NSView {
    let ve = NSVisualEffectView(frame: .zero)
    ve.material = .hudWindow
    ve.state = .active
    ve.wantsLayer = true
    ve.layer?.cornerRadius = cornerRadius
    ve.layer?.masksToBounds = true
    return ve
}

func embedInCard(_ card: NSView, _ content: NSView) {
    content.frame = card.bounds
    content.autoresizingMask = [.width, .height]
    card.addSubview(content)
}

func makeGlassPanel(cornerRadius: CGFloat) -> NSView {
    let ve = NSVisualEffectView(frame: .zero)
    ve.material = .hudWindow
    ve.state = .active
    ve.wantsLayer = true
    ve.layer?.cornerRadius = cornerRadius
    ve.layer?.masksToBounds = true
    ve.layer?.borderWidth = 0.5
    ve.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
    return ve
}
