import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "HushKey/Assets.xcassets/AppIcon.appiconset")
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

for (filename, pixelSize) in sizes {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
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
    let side = CGFloat(pixelSize)
    let canvas = CGRect(x: 0, y: 0, width: side, height: side)
    let scale = side / 1024

    let tile = NSBezierPath(roundedRect: canvas.insetBy(dx: side * 0.025, dy: side * 0.025), xRadius: side * 0.22, yRadius: side * 0.22)
    let background = NSGradient(colors: [color(0.055, 0.09, 0.19), color(0.08, 0.22, 0.32), color(0.055, 0.11, 0.22)])!
    background.draw(in: tile, angle: 315)

    let halo = NSBezierPath(ovalIn: CGRect(x: side * 0.22, y: side * 0.25, width: side * 0.58, height: side * 0.58))
    color(0.12, 0.78, 0.72, 0.12).setFill()
    halo.fill()

    let bars: [(CGFloat, CGFloat)] = [
        (230, 130), (320, 250), (410, 360), (500, 480), (590, 365),
        (680, 275), (770, 180)
    ]
    let barGradient = NSGradient(colors: [color(0.56, 1.0, 0.86), color(0.28, 0.84, 0.91)])!
    for (x, height) in bars {
        let rect = CGRect(x: x * scale, y: (512 - height / 2) * scale, width: 58 * scale, height: height * scale)
        let bar = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        barGradient.draw(in: bar, angle: 270)
    }

    // A quiet text cursor makes the motion-to-text purpose clear at a glance.
    let cursor = NSBezierPath(roundedRect: CGRect(x: 858 * scale, y: 440 * scale, width: 18 * scale, height: 142 * scale), xRadius: 9 * scale, yRadius: 9 * scale)
    color(0.97, 0.99, 1.0).setFill()
    cursor.fill()
    let cursorDot = NSBezierPath(ovalIn: CGRect(x: 854 * scale, y: 408 * scale, width: 26 * scale, height: 26 * scale))
    color(0.44, 0.97, 0.79).setFill()
    cursorDot.fill()

    let rim = NSBezierPath(roundedRect: canvas.insetBy(dx: side * 0.027, dy: side * 0.027), xRadius: side * 0.22, yRadius: side * 0.22)
    color(0.78, 0.96, 1.0, 0.16).setStroke()
    rim.lineWidth = max(1, side * 0.008)
    rim.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(filename), options: .atomic)
}
