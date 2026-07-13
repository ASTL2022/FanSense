import Cocoa

final class TransparentPanel: NSPanel {
    override var isOpaque: Bool { get { return false } set {} }
    override var backgroundColor: NSColor! { get { return .clear } set {} }
}
