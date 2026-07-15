// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Cocoa

final class TransparentPanel: NSPanel {
    override var isOpaque: Bool { get { return false } set {} }
    override var backgroundColor: NSColor! { get { return .clear } set {} }
}
