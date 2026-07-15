// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

// Build-time tool: generates 30 pre-rotated fan icon PNGs → Resources/fan_frame_NN.png
// Run once; build.sh skips if frames already exist.
import AppKit

let frameCount = 30
// Menu bar icons are 13pt (matching setupIcon SymbolConfiguration).
// We render at 4× oversample (104px @2x = 208px) so anti-aliasing is
// consistent across all 30 angles, eliminating rotation jitter.
// The bitmap's `size` is set to 13×13pt so NSImage loads it back at the right logical size.
let ptSize: CGFloat = 13
let scale: CGFloat = 2.0              // Retina
let oversample: CGFloat = 4.0         // 4× oversample for smooth rotation
let pxSize: Int = Int(ceil(ptSize * scale * oversample))   // 104

guard let sym = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: ptSize, weight: .medium)) else {
    fputs("gen_frames: cannot load fan.fill SF Symbol\n", stderr); exit(1)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let drawSz = ptSize * scale * oversample

for i in 0..<frameCount {
    let angle = CGFloat(i) * 2.0 * .pi / CGFloat(frameCount)

    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxSize, pixelsHigh: pxSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fputs("gen_frames: bitmap alloc failed\n", stderr); exit(1) }

    // size = pt dimensions — NSImage will pick the right rep at display time
    bmp.size = NSSize(width: ptSize, height: ptSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)

    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.translateBy(x: CGFloat(pxSize) / 2, y: CGFloat(pxSize) / 2)
        ctx.rotate(by: -angle)
        sym.draw(in: NSRect(x: -drawSz / 2, y: -drawSz / 2, width: drawSz, height: drawSz))
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bmp.representation(using: .png, properties: [:]) else {
        fputs("gen_frames: encode failed frame \(i)\n", stderr); exit(1)
    }

    let path = String(format: "%@/fan_frame_%02d.png", outDir, i)
    do { try png.write(to: URL(fileURLWithPath: path)) }
    catch { fputs("gen_frames: write failed: \(error)\n", stderr); exit(1) }
}

print("gen_frames: wrote \(frameCount) frames to \(outDir)")
