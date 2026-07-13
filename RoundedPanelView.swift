import Cocoa
import SwiftUI

func makeGlass(cornerRadius: CGFloat, interactive: Bool = false) -> NSView {
    let wrapper = NSView(frame: .zero)
    wrapper.wantsLayer = true
    wrapper.layer?.cornerRadius = cornerRadius
    wrapper.layer?.masksToBounds = true

    let hosting = NSHostingView(rootView: GlassBg(cornerRadius: cornerRadius))
    hosting.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(hosting)
    NSLayoutConstraint.activate([
        hosting.topAnchor.constraint(equalTo: wrapper.topAnchor),
        hosting.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        hosting.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
        hosting.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
    ])
    return wrapper
}

func setGlassContentView(_ glass: NSView, _ content: NSView) {
    content.frame = glass.bounds
    content.autoresizingMask = [.width, .height]
    glass.addSubview(content)
}

func makeGlassContainer() -> NSView {
    let container = NSView(frame: .zero)
    return container
}

func applySystemGlassTint(_ glass: NSView) {
    let amount = CFPreferencesCopyAppValue("NSGlassTintAmount" as CFString, kCFPreferencesAnyApplication) as? Float ?? 0
    let alpha = 0.04 + Double(amount) * 0.40
    for sub in glass.subviews {
        if let hosting = sub as? NSHostingView<GlassBg> {
            var bg = hosting.rootView
            bg.tintAlpha = alpha
            hosting.rootView = bg
        }
    }
}

func applySystemGlassTintToAll(_ views: [NSView]) {
    for v in views { applySystemGlassTint(v) }
}

struct GlassBg: View {
    var cornerRadius: CGFloat = 14
    var tintAlpha: Double = 0.04

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(tintAlpha))
            }
    }
}
