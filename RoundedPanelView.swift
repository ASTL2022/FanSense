// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

func makeCard(cornerRadius: CGFloat) -> NSView {
    let wrapper = NSView(frame: .zero)
    wrapper.wantsLayer = true
    wrapper.layer?.cornerRadius = cornerRadius
    wrapper.layer?.masksToBounds = true

    let ve = NSVisualEffectView(frame: .zero)
    ve.material = .hudWindow
    ve.state = .active
    ve.autoresizingMask = [.width, .height]
    ve.frame = wrapper.bounds
    wrapper.addSubview(ve)
    return wrapper
}

func embedInCard(_ card: NSView, _ content: NSView) {
    content.frame = card.bounds
    content.autoresizingMask = [.width, .height]
    card.addSubview(content)
}

func makeGlassPanel(cornerRadius: CGFloat) -> NSView {
    let wrapper = NSView(frame: .zero)
    wrapper.wantsLayer = true
    wrapper.layer?.cornerRadius = cornerRadius
    wrapper.layer?.masksToBounds = true
    wrapper.layer?.borderWidth = 0.5
    wrapper.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor

    let ve = NSVisualEffectView(frame: .zero)
    ve.material = .hudWindow
    ve.state = .active
    ve.autoresizingMask = [.width, .height]
    ve.frame = wrapper.bounds
    wrapper.addSubview(ve)
    return wrapper
}
