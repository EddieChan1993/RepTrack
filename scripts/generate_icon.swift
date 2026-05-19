#!/usr/bin/env swift
// BananaTrack icon generator — flat cartoon banana on dark background
import AppKit

// MARK: - Drawing (all coordinates in 1024×1024, AppKit origin = bottom-left)

func drawIcon(size: CGFloat) {
    let sc = size / 1024

    // ── Background ──────────────────────────────────────────────────────────
    NSColor(red: 0.133, green: 0.082, blue: 0.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                 xRadius: size * 0.22, yRadius: size * 0.22).fill()

    // ── Helper: scale point ─────────────────────────────────────────────────
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * sc, y: y * sc) }

    // ── Banana body — diagonal crescent (lower-left tip → upper-right tip) ──
    // AppKit: y increases upward. Outer curve bows toward upper-left.
    let body = NSBezierPath()
    body.move(to: pt(195, 195))          // lower-left tip (tip end)
    body.curve(to: pt(820, 750),         // upper-right tip (stem end)
               controlPoint1: pt(100, 560),
               controlPoint2: pt(490, 930))
    body.lineWidth  = 188 * sc
    body.lineCapStyle = .round
    NSColor(red: 1.0, green: 0.847, blue: 0.0, alpha: 1).setStroke()
    body.stroke()

    // ── Highlight streak ─────────────────────────────────────────────────────
    let hi = NSBezierPath()
    hi.move(to: pt(245, 245))
    hi.curve(to: pt(780, 730),
             controlPoint1: pt(130, 545),
             controlPoint2: pt(475, 905))
    hi.lineWidth = 62 * sc
    hi.lineCapStyle = .round
    NSColor(red: 1.0, green: 0.980, blue: 0.70, alpha: 0.52).setStroke()
    hi.stroke()

    // ── Underside shadow ─────────────────────────────────────────────────────
    let sh = NSBezierPath()
    sh.move(to: pt(230, 165))
    sh.curve(to: pt(840, 720),
             controlPoint1: pt(130, 530),
             controlPoint2: pt(520, 900))
    sh.lineWidth = 50 * sc
    sh.lineCapStyle = .round
    NSColor(red: 0.72, green: 0.48, blue: 0.0, alpha: 0.42).setStroke()
    sh.stroke()

    // ── Stem (brown nub at upper-right tip) ──────────────────────────────────
    let stem = NSBezierPath()
    stem.move(to: pt(820, 750))
    stem.curve(to: pt(890, 840),
               controlPoint1: pt(840, 768),
               controlPoint2: pt(875, 805))
    stem.lineWidth = 26 * sc
    stem.lineCapStyle = .round
    NSColor(red: 0.50, green: 0.32, blue: 0.10, alpha: 1).setStroke()
    stem.stroke()
}

// MARK: - Export

func makeIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    bmp.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: bmp)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    drawIcon(size: s)
    NSGraphicsContext.restoreGraphicsState()

    return bmp.representation(using: .png, properties: [.interlaced: false])
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/banana_icons"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let data = makeIcon(size: size) else { print("✗ \(size)"); continue }
    let path = "\(outDir)/icon_\(size).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("✓ icon_\(size).png")
}
