// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

// MARK: - Panel Controller

@MainActor
final class PanelController {
    private(set) var isVisible: Bool = false
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var statusButton: NSStatusBarButton?
    private var lastHideTime = Date.distantPast

    var onVisibilityChange: ((Bool) -> Void)?

    let headerView     = HeaderView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: HeaderView.h))
    let tempBarView    = TempBarView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: TempBarView.height(count: 3)))
    let batteryBarView = BatteryBarView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: BatteryBarView.h))
    let efficiencyView = EfficiencyView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: EfficiencyView.viewH))
    let fanView        = FanView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: FanView.h))
    let metricBarView  = MetricBarView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: MetricBarView.height(count: 3)))
    let netBarView     = NetBarView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: NetBarView.height()))
    let diskBarView    = MetricBarView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: MetricBarView.height(count: 2)))

    func setup(statusButton: NSStatusBarButton?) {
        self.statusButton = statusButton
        let contentView = makeContentView()
        let totalH = contentView.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let panelH = min(totalH, maxH)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: panelH))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = contentView

        let panelView = makeGlassPanel(cornerRadius: Layout.PANEL_R)
        panelView.frame = NSRect(x: 0, y: 0, width: Layout.W, height: panelH)
        panelView.addSubview(scroll)
        scroll.frame = panelView.bounds
        scroll.autoresizingMask = [.width, .height]

        let p = TransparentPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.W, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = false
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = panelView
        self.panel = p
    }

    func show() {
        guard let p = panel, let btn = statusButton,
              let screen = btn.window?.screen ?? NSScreen.main else { return }

        let btnRect = btn.window!.convertToScreen(btn.frame)
        let x = min(btnRect.midX - Layout.W / 2, screen.visibleFrame.maxX - Layout.W)
        let y = btnRect.minY - p.frame.height - 2

        p.setFrameOrigin(NSPoint(x: max(x, screen.visibleFrame.minX), y: y))
        p.makeKeyAndOrderFront(nil)

        isVisible = true
        onVisibilityChange?(true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.hide()
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        lastHideTime = Date()
        onVisibilityChange?(false)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func statusItemClicked() {
        if isVisible {
            hide()
            return
        }
        // mouse down 已被全局监听关掉时，mouse up 不要把它重新打开
        if Date().timeIntervalSince(lastHideTime) < 0.3 { return }
        show()
    }

    func relayout() {
        guard let p = panel, let panelView = p.contentView,
              let scroll = panelView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
        else { return }
        let cv = makeContentView()
        scroll.documentView = cv
        let totalH = cv.frame.height
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let h = min(totalH, maxH)
        var f = p.frame; let top = f.origin.y + f.height
        f.size.height = h; f.origin.y = top - h
        p.setFrame(f, display: true, animate: false)
        panelView.frame = NSRect(x: 0, y: 0, width: Layout.W, height: h)
        scroll.frame = panelView.bounds
    }
}

// MARK: - Content View Assembly (private to PanelController)

private extension PanelController {

    func makeContentView() -> NSView {
        let hPad:  CGFloat = 8
        let colGap: CGFloat = 8
        let colW = (Layout.W - hPad * 2 - colGap) / 2

        let leftGroups:  [[NSView]] = [[batteryBarView], [efficiencyView], [fanView]]
        let rightGroups: [[NSView]] = [[tempBarView], [metricBarView], [netBarView], [diskBarView]]

        func makeCardView(_ views: [NSView], width: CGFloat) -> NSView {
            let vPad: CGFloat = 8
            var cardH: CGFloat = vPad
            for v in views { cardH += v.frame.height }
            cardH += vPad
            let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))
            var vy = vPad
            for v in views.reversed() {
                v.frame = NSRect(x: 0, y: vy, width: width, height: v.frame.height)
                box.addSubview(v)
                vy += v.frame.height
            }
            let card = makeCard(cornerRadius: Layout.CARD_R)
            card.frame = NSRect(x: 0, y: 0, width: width, height: cardH)
            embedInCard(card, box)
            return card
        }

        func buildCol(_ groups: [[NSView]], width: CGFloat) -> ([NSView], CGFloat) {
            var cards: [NSView] = []
            var h: CGFloat = Layout.GAP
            for g in groups {
                let c = makeCardView(g, width: width)
                cards.append(c)
                h += c.frame.height + Layout.GAP
            }
            return (cards, h)
        }

        let (leftCards,  leftH)  = buildCol(leftGroups,  width: colW)
        let (rightCards, rightH) = buildCol(rightGroups, width: colW)
        let contentH = max(leftH, rightH)

        let c = NSView(frame: NSRect(x: 0, y: 0, width: Layout.W, height: contentH))
        let lx = hPad; var ly = contentH - Layout.GAP
        for card in leftCards { ly -= card.frame.height; card.frame.origin = NSPoint(x: lx, y: ly); c.addSubview(card); ly -= Layout.GAP }
        let rx = hPad + colW + colGap; var ry = contentH - Layout.GAP
        for card in rightCards { ry -= card.frame.height; card.frame.origin = NSPoint(x: rx, y: ry); c.addSubview(card); ry -= Layout.GAP }
        return c
    }
}
