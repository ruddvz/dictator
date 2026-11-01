import AppKit
import Foundation

let appIconURL = URL(fileURLWithPath: "HushKey/Assets.xcassets/AppIcon.appiconset")
let menuIconURL = URL(fileURLWithPath: "HushKey/Assets.xcassets/HushKeyMenuBar.imageset")
try FileManager.default.createDirectory(at: appIconURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuIconURL, withIntermediateDirectories: true)

let appIconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func renderPNG(size: Int, to url: URL, draw: (CGFloat) -> Void) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    context.cgContext.setShouldAntialias(true)
    draw(CGFloat(size) / 1024)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

func drawAppIcon(scale: CGFloat) {
    let side = 1024 * scale
    let canvas = CGRect(x: 0, y: 0, width: side, height: side)
    let backdrop = NSBezierPath(rect: canvas)
    NSGradient(colors: [color(0.035, 0.10, 0.20), color(0.055, 0.25, 0.34), color(0.055, 0.16, 0.27)])!
        .draw(in: backdrop, angle: 315)

    let glowPath = NSBezierPath(ovalIn: CGRect(x: 130 * scale, y: 230 * scale, width: 760 * scale, height: 760 * scale))
    NSGradient(colors: [color(0.22, 0.94, 0.77, 0.18), color(0.22, 0.94, 0.77, 0)])!
        .draw(in: glowPath, relativeCenterPosition: CGPoint(x: -0.22, y: -0.14))

    // Two faint rings suggest a small motion signal without implying microphone audio.
    for (inset, opacity) in [(52.0, 0.16), (22.0, 0.09)] {
        let ring = NSBezierPath(ovalIn: CGRect(x: (inset + 74) * scale, y: (inset + 74) * scale,
                                               width: (876 - inset * 2) * scale, height: (876 - inset * 2) * scale))
        color(0.57, 0.99, 0.91, opacity).setStroke()
        ring.lineWidth = 9 * scale
        ring.stroke()
    }

    let keyBase = roundedRect(CGRect(x: 216 * scale, y: 184 * scale, width: 592 * scale, height: 656 * scale), radius: 156 * scale)
    let shadow = NSShadow()
    shadow.shadowColor = color(0.008, 0.035, 0.08, 0.65)
    shadow.shadowOffset = NSSize(width: 0, height: -28 * scale)
    shadow.shadowBlurRadius = 38 * scale
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSGradient(colors: [color(0.30, 0.89, 0.81), color(0.12, 0.58, 0.69)])!
        .draw(in: keyBase, angle: 270)
    NSGraphicsContext.restoreGraphicsState()

    let keyFace = roundedRect(keyBase.bounds.insetBy(dx: 17 * scale, dy: 17 * scale), radius: 142 * scale)
    NSGradient(colors: [color(0.91, 1.0, 0.94), color(0.61, 0.95, 0.87), color(0.43, 0.82, 0.84)])!
        .draw(in: keyFace, angle: 270)
    color(1, 1, 1, 0.62).setStroke()
    keyFace.lineWidth = 3 * scale
    keyFace.stroke()

    let highlight = NSBezierPath()
    highlight.move(to: CGPoint(x: 336 * scale, y: 756 * scale))
    highlight.curve(to: CGPoint(x: 682 * scale, y: 756 * scale),
                    controlPoint1: CGPoint(x: 430 * scale, y: 782 * scale),
                    controlPoint2: CGPoint(x: 590 * scale, y: 782 * scale))
    color(1, 1, 1, 0.56).setStroke()
    highlight.lineWidth = 8 * scale
    highlight.lineCapStyle = .round
    highlight.stroke()

    let h = NSBezierPath()
    h.move(to: CGPoint(x: 382 * scale, y: 350 * scale))
    h.line(to: CGPoint(x: 382 * scale, y: 676 * scale))
    h.move(to: CGPoint(x: 642 * scale, y: 350 * scale))
    h.line(to: CGPoint(x: 642 * scale, y: 676 * scale))
    h.move(to: CGPoint(x: 382 * scale, y: 512 * scale))
    h.curve(to: CGPoint(x: 642 * scale, y: 512 * scale),
            controlPoint1: CGPoint(x: 462 * scale, y: 465 * scale),
            controlPoint2: CGPoint(x: 562 * scale, y: 559 * scale))
    h.lineWidth = 58 * scale
    h.lineCapStyle = .round
    h.lineJoinStyle = .round
    color(0.035, 0.17, 0.24).setStroke()
    h.stroke()
}

func drawMenuBarMark(scale: CGFloat) {
    let outer = roundedRect(CGRect(x: 192 * scale, y: 202 * scale, width: 640 * scale, height: 620 * scale), radius: 142 * scale)
    color(1, 1, 1).setStroke()
    outer.lineWidth = 68 * scale
    outer.stroke()

    let h = NSBezierPath()
    h.move(to: CGPoint(x: 390 * scale, y: 350 * scale))
    h.line(to: CGPoint(x: 390 * scale, y: 676 * scale))
    h.move(to: CGPoint(x: 634 * scale, y: 350 * scale))
    h.line(to: CGPoint(x: 634 * scale, y: 676 * scale))
    h.move(to: CGPoint(x: 390 * scale, y: 512 * scale))
    h.curve(to: CGPoint(x: 634 * scale, y: 512 * scale),
            controlPoint1: CGPoint(x: 464 * scale, y: 468 * scale),
            controlPoint2: CGPoint(x: 560 * scale, y: 556 * scale))
    color(1, 1, 1).setStroke()
    h.lineWidth = 74 * scale
    h.lineCapStyle = .round
    h.lineJoinStyle = .round
    h.stroke()
}

for (filename, size) in appIconSizes {
    try renderPNG(size: size, to: appIconURL.appendingPathComponent(filename), draw: drawAppIcon)
}
try renderPNG(size: 18, to: menuIconURL.appendingPathComponent("HushKeyMenuBar.png"), draw: drawMenuBarMark)
try renderPNG(size: 36, to: menuIconURL.appendingPathComponent("HushKeyMenuBar@2x.png"), draw: drawMenuBarMark)
