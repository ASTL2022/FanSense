// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

// gen_icon.swift — macOS 26 Liquid Glass single-layer fan icon
// Design: translucent frosted glass blades on transparent ground,
// soft depth through subtle shadows and specular highlights.
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// ── Design tokens (macOS 26 Liquid Glass palette) ───────────────────────────
// Primary glass tint: cool aqua-teal
let glassA = NSColor(red: 0.20, green: 0.78, blue: 0.82, alpha: 1.0) // bright aqua
let glassB = NSColor(red: 0.10, green: 0.55, blue: 0.70, alpha: 1.0) // deeper teal
let glassC = NSColor(red: 0.35, green: 0.88, blue: 0.92, alpha: 1.0) // pale cyan highlight

// ── Helpers ────────────────────────────────────────────────────────────────

func squirclePath(in rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect,
           cornerWidth:  rect.width * 0.2237,
           cornerHeight: rect.width * 0.2237,
           transform: nil)
}

/// Single fan blade — organic, flowing shape.
/// Tip is at +Y, base straddles X axis near origin.
/// Designed to look like a modern glass fan blade with softer curves.
func bladePath(r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let hub:  CGFloat = r * 0.10      // hub radius
    let tipY: CGFloat = r * 0.60      // how far the blade tip extends
    let tipW: CGFloat = r * 0.18      // half-width at tip
    let midW: CGFloat = r * 0.32      // half-width at mid-body

    // Start at right edge of hub
    path.move(to: CGPoint(x: hub, y: 0))

    // Outer edge: sweep up and slightly inward toward tip
    path.addCurve(
        to:       CGPoint(x:  tipW,      y:  tipY),
        control1: CGPoint(x:  midW * 1.1, y:  r * 0.15),
        control2: CGPoint(x:  midW * 0.9, y:  r * 0.42))

    // Tip cap: gentle rounded arc
    path.addCurve(
        to:       CGPoint(x: -tipW,      y:  tipY),
        control1: CGPoint(x:  tipW * 0.7, y:  tipY + r * 0.08),
        control2: CGPoint(x: -tipW * 0.7, y:  tipY + r * 0.08))

    // Inner edge: return sweep toward hub
    path.addCurve(
        to:       CGPoint(x: -hub, y: 0),
        control1: CGPoint(x: -midW * 0.9, y:  r * 0.42),
        control2: CGPoint(x: -midW * 1.1, y:  r * 0.15))

    path.closeSubpath()
    return path
}

// ── Main draw ──────────────────────────────────────────────────────────────

func drawIcon(size: Int) -> NSBitmapImageRep {
    let s  = CGFloat(size)
    let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bmp.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    let ctx = NSGraphicsContext.current!.cgContext

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let r    = s * 0.5
    let cx   = s * 0.5
    let cy   = s * 0.5
    let cs   = CGColorSpaceCreateDeviceRGB()

    // ── 1. Squircle clip (system will apply this; we respect it) ────────────
    let sq = squirclePath(in: rect)
    ctx.addPath(sq); ctx.clip()

    // ── 2. Background: transparent — just a whisper of frosted glass ────────
    // Ultra-subtle cool-toned radial vignette that fades to fully transparent
    let bgC = [
        NSColor(red: 0.92, green: 0.97, blue: 1.00, alpha: 0.12).cgColor,
        NSColor(red: 0.88, green: 0.95, blue: 0.99, alpha: 0.04).cgColor,
        NSColor(red: 0.85, green: 0.93, blue: 0.98, alpha: 0.00).cgColor,
    ] as CFArray
    let bgL: [CGFloat] = [0, 0.4, 1]
    let bgG = CGGradient(colorsSpace: cs, colors: bgC, locations: bgL)!
    ctx.drawRadialGradient(bgG,
        startCenter: CGPoint(x: cx, y: cy), startRadius: r * 0.05,
        endCenter:   CGPoint(x: cx, y: cy), endRadius:   r * 1.05,
        options: [])

    // ── 3. Soft ambient glow behind blades ──────────────────────────────────
    let glowC = [
        glassA.withAlphaComponent(0.15).cgColor,
        glassA.withAlphaComponent(0.00).cgColor,
    ] as CFArray
    let glowL: [CGFloat] = [0, 1]
    let glowG = CGGradient(colorsSpace: cs, colors: glowC, locations: glowL)!
    ctx.drawRadialGradient(glowG,
        startCenter: CGPoint(x: cx, y: cy), startRadius: r * 0.08,
        endCenter:   CGPoint(x: cx, y: cy), endRadius:   r * 0.72,
        options: [])

    // ── 4. Fan blades — frosted glass body ──────────────────────────────────
    let blade = bladePath(r: r)

    // Blade body gradient: glassA at tip → glassB at base
    let bladeC = [
        glassA.withAlphaComponent(0.78).cgColor,
        glassA.withAlphaComponent(0.55).cgColor,
        glassB.withAlphaComponent(0.70).cgColor,
    ] as CFArray
    let bladeL: [CGFloat] = [0, 0.55, 1]
    let bladeG = CGGradient(colorsSpace: cs, colors: bladeC, locations: bladeL)!

    for i in 0..<3 {
        let angle = CGFloat(i) * (2 * .pi / 3) + (.pi / 2)
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy); ctx.rotate(by: angle)
        ctx.translateBy(x: -cx, y: -cy)

        // Soft drop shadow for glass depth
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: s * 0.004, height: -s * 0.012),
            blur:   s * 0.035,
            color:  NSColor(red: 0.05, green: 0.25, blue: 0.30, alpha: 0.28).cgColor)
        ctx.addPath(blade)
        ctx.setFillColor(glassB.withAlphaComponent(0.50).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Blade body fill
        ctx.addPath(blade); ctx.clip()
        ctx.drawLinearGradient(bladeG,
            start: CGPoint(x: cx, y: cy + r * 0.58),
            end:   CGPoint(x: cx, y: cy - r * 0.02),
            options: [])
        ctx.restoreGState()
    }

    // ── 5. Internal glass refraction — soft white bloom across blades ───────
    for i in 0..<3 {
        let angle = CGFloat(i) * (2 * .pi / 3) + (.pi / 2)
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy); ctx.rotate(by: angle)
        ctx.translateBy(x: -cx, y: -cy)
        ctx.addPath(blade); ctx.clip()

        // Diagonal light streak simulating glass refraction
        let streakC = [
            NSColor(white: 1, alpha: 0.35).cgColor,
            NSColor(white: 1, alpha: 0.08).cgColor,
            NSColor(white: 1, alpha: 0.00).cgColor,
        ] as CFArray
        let streakL: [CGFloat] = [0, 0.45, 1]
        let streakG = CGGradient(colorsSpace: cs, colors: streakC, locations: streakL)!
        ctx.drawLinearGradient(streakG,
            start: CGPoint(x: cx + r * 0.30, y: cy + r * 0.45),
            end:   CGPoint(x: cx - r * 0.30, y: cy - r * 0.15),
            options: [])
        ctx.restoreGState()
    }

    // ── 6. Leading edge specular highlight (thin bright line per blade) ─────
    for i in 0..<3 {
        let angle = CGFloat(i) * (2 * .pi / 3) + (.pi / 2)
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy); ctx.rotate(by: angle)
        ctx.translateBy(x: -cx, y: -cy)
        ctx.addPath(blade); ctx.clip()

        // Bright edge on the right (leading) side
        let edgeC = [
            NSColor(white: 1, alpha: 0.55).cgColor,
            NSColor(white: 1, alpha: 0.00).cgColor,
        ] as CFArray
        let edgeL: [CGFloat] = [0, 1]
        let edgeG = CGGradient(colorsSpace: cs, colors: edgeC, locations: edgeL)!
        ctx.drawLinearGradient(edgeG,
            start: CGPoint(x: cx + r * 0.12, y: cy + r * 0.25),
            end:   CGPoint(x: cx - r * 0.06, y: cy + r * 0.25),
            options: [])
        ctx.restoreGState()
    }

    // ── 7. Hub — frosted glass pill ─────────────────────────────────────────
    let hubR    = r * 0.10
    let hubRect = CGRect(x: cx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2)

    // Subtle hub shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.004),
        blur:   s * 0.012,
        color:  NSColor(red: 0.05, green: 0.20, blue: 0.28, alpha: 0.35).cgColor)
    ctx.setFillColor(NSColor(white: 0.92, alpha: 0.85).cgColor)
    ctx.fillEllipse(in: hubRect)
    ctx.restoreGState()

    // Hub glass gradient
    let hubBodyC = [
        NSColor(white: 1.00, alpha: 0.90).cgColor,
        NSColor(white: 0.88, alpha: 0.70).cgColor,
        NSColor(white: 0.78, alpha: 0.60).cgColor,
    ] as CFArray
    let hubBodyL: [CGFloat] = [0, 0.5, 1]
    let hubBodyG = CGGradient(colorsSpace: cs, colors: hubBodyC, locations: hubBodyL)!
    ctx.saveGState()
    ctx.addEllipse(in: hubRect); ctx.clip()
    ctx.drawLinearGradient(hubBodyG,
        start: CGPoint(x: cx, y: hubRect.maxY),
        end:   CGPoint(x: cx, y: hubRect.minY),
        options: [])
    ctx.restoreGState()

    // Hub rim — thin glass edge
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.50).cgColor)
    ctx.setLineWidth(s * 0.003)
    ctx.strokeEllipse(in: hubRect.insetBy(dx: s * 0.002, dy: s * 0.002))

    // Hub inner specular dot
    let dotR = hubR * 0.35
    let dotRect = CGRect(x: cx + hubR * 0.20, y: cy + hubR * 0.25,
                         width: dotR * 2, height: dotR * 1.2)
    let dotPath = CGPath(ellipseIn: dotRect, transform: nil)
    ctx.setFillColor(NSColor(white: 1, alpha: 0.70).cgColor)
    ctx.addPath(dotPath); ctx.fillPath()

    // ── 8. Top rim — glass edge highlight across the squircle ───────────────
    ctx.resetClip()
    ctx.addPath(sq)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.30).cgColor)
    ctx.setLineWidth(s * 0.005)
    ctx.strokePath()

    // Subtle inner rim glow (top edge only, simulating light catch)
    let rimC = [
        NSColor(white: 1, alpha: 0.25).cgColor,
        NSColor(white: 1, alpha: 0.00).cgColor,
    ] as CFArray
    let rimL: [CGFloat] = [0, 1]
    let rimG = CGGradient(colorsSpace: cs, colors: rimC, locations: rimL)!
    ctx.saveGState()
    ctx.addPath(sq); ctx.clip()
    ctx.drawLinearGradient(rimG,
        start: CGPoint(x: cx, y: s * 0.96),
        end:   CGPoint(x: cx, y: s * 0.82),
        options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return bmp
}

// ── Iconset output ──────────────────────────────────────────────────────────

func writePNG(_ bmp: NSBitmapImageRep, to path: String) {
    guard let data = bmp.representation(using: .png, properties: [:]) else {
        fputs("gen_icon: encode failed \(path)\n", stderr); exit(1)
    }
    do { try data.write(to: URL(fileURLWithPath: path)) }
    catch { fputs("gen_icon: write failed \(path): \(error)\n", stderr); exit(1) }
}

let iconsetPath = outDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath,
                                          withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

var cache: [Int: NSBitmapImageRep] = [:]
for (name, px) in specs {
    if cache[px] == nil { cache[px] = drawIcon(size: px) }
    writePNG(cache[px]!, to: iconsetPath + "/" + name)
    print("  wrote \(name) (\(px)px)")
}
print("gen_icon: done → \(iconsetPath)")
