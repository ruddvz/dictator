import AppKit
import Foundation

// Draws HushKey's app icon and menu bar glyph: a fog keycap carrying the sage breath ribbon,
// the same form as `BreathRibbon` and `MorphIcon` in the app. Colours are the Fog & sage
// tokens from docs/DESIGN_SYSTEM.md. Run from the repository root; package-app.sh runs it.

let appIconURL = URL(fileURLWithPath: "HushKey/Assets.xcassets/AppIcon.appiconset")
let menuIconURL = URL(fileURLWithPath: "HushKey/Assets.xcassets/HushKeyMenuBar.imageset")
let liveMenuIconURL = URL(fileURLWithPath: "HushKey/Assets.xcassets/HushKeyMenuBarLive.imageset")
for url in [appIconURL, menuIconURL, liveMenuIconURL] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

let appIconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

func renderPNG(width: Int, height: Int, to url: URL, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    draw(context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

/// Superellipse close to the macOS icon squircle; a lower exponent gives a rounder corner.
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 360
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// The breath ribbon: a lens tapered to fine tips whose spine makes one soft S, like the hush
/// in `MorphIcon`. `swell` > 1 is the ribbon opened by a voice: fuller, with a calmer spine.
func ribbon(in rect: CGRect, swell: CGFloat = 1, taper: CGFloat = 1.35) -> CGPath {
    let samples = 120
    var top: [CGPoint] = [], bottom: [CGPoint] = []
    for index in 0...samples {
        let u = CGFloat(index) / CGFloat(samples)
        let x = rect.minX + u * rect.width
        let spine = rect.midY + rect.height * 0.22 * sin(2 * .pi * u) / swell
        let half = rect.height * 0.26 * pow(sin(.pi * u), taper) * (1 + (swell - 1) * 0.7)
        top.append(CGPoint(x: x, y: spine + half))
        bottom.append(CGPoint(x: x, y: spine - half))
    }
    let path = CGMutablePath()
    path.addLines(between: top + bottom.reversed())
    path.closeSubpath()
    return path
}

/// Fills a ribbon and rounds its two tips with a thin round-joined stroke of the same path.
func fillRibbon(_ context: CGContext, _ path: CGPath, tip: CGFloat) {
    context.addPath(path)
    context.fillPath()
    context.addPath(path)
    context.setLineWidth(tip)
    context.setLineJoin(.round)
    context.strokePath()
}

/// Fills `path` with a linear gradient from `top` to `bottom` (y-up coordinates).
func paint(_ context: CGContext, _ path: CGPath, _ fill: CGGradient, top: CGFloat, bottom: CGFloat, x: CGFloat = 512) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(fill, start: CGPoint(x: x, y: top), end: CGPoint(x: x, y: bottom), options: extend)
    context.restoreGState()
}

/// A hairline along the top of `path`, fading out by `fade` of its height.
func topLight(_ context: CGContext, _ path: CGPath, rect: CGRect, width: CGFloat, alpha: CGFloat, fade: CGFloat = 0.5) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.addPath(path)
    context.setLineWidth(width * 2)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(gradient([hex(0xFFFFFF, alpha), hex(0xFFFFFF, 0)], [0, fade]),
                               start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: extend)
    context.restoreGState()
}

func drawAppIcon(_ context: CGContext, side: CGFloat) {
    // Shadows are set in device pixels, so their offsets and blurs are multiplied by `k`.
    let k = side / 1024
    let small = side <= 32
    context.scaleBy(x: k, y: k)

    // Body on the macOS grid: 824 squircle inset 100, dropped shadow below.
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = squircle(bodyRect)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: hex(0x000000, 0.3))
    context.addPath(body)
    context.setFillColor(hex(0x18201C))
    context.fillPath()
    context.restoreGState()

    // heroBase, lifted toward the top, with the hero's sage glow and fog mist.
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(gradient([hex(0x2C3A33), hex(0x18201C), hex(0x0E1311)], [0, 0.55, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: extend)
    if !small {
        context.drawRadialGradient(gradient([hex(0x7FB39C, 0.30), hex(0x7FB39C, 0)], [0, 1]),
                                   startCenter: CGPoint(x: 330, y: 800), startRadius: 0,
                                   endCenter: CGPoint(x: 330, y: 800), endRadius: 540, options: [])
        context.drawRadialGradient(gradient([hex(0x8FA7B4, 0.14), hex(0x8FA7B4, 0)], [0, 1]),
                                   startCenter: CGPoint(x: 800, y: 200), startRadius: 0,
                                   endCenter: CGPoint(x: 800, y: 200), endRadius: 440, options: [])
    }
    context.restoreGState()
    if !small { topLight(context, body, rect: bodyRect, width: 3, alpha: 0.22, fade: 0.6) }

    // Keycap: a sage-fog skirt with the top face set high on it, so the front wall shows.
    let skirtRect = small ? CGRect(x: 190, y: 190, width: 644, height: 644) : CGRect(x: 228, y: 204, width: 568, height: 600)
    let skirt = squircle(skirtRect, exponent: small ? 3.6 : 4)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -40 * k), blur: 80 * k, color: hex(0x000000, 0.5))
    context.addPath(skirt)
    context.setFillColor(hex(0x9DB5A8))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 14 * k, color: hex(0x000000, 0.4))
    context.addPath(skirt)
    context.fillPath()
    context.restoreGState()
    // keycap → keycapEdge, deepening toward the front wall.
    paint(context, skirt, gradient([hex(0xDDE7E1), hex(0xB4C8BC), hex(0x86A393)], [0, 0.45, 1]),
          top: skirtRect.maxY, bottom: skirtRect.minY)
    if !small {
        // Round the side walls: a touch darker toward both edges.
        context.saveGState()
        context.addPath(skirt)
        context.clip()
        context.drawLinearGradient(gradient([hex(0x2A3A33, 0.16), hex(0x2A3A33, 0), hex(0x2A3A33, 0), hex(0x2A3A33, 0.16)],
                                            [0, 0.18, 0.82, 1]),
                                   start: CGPoint(x: skirtRect.minX, y: 0), end: CGPoint(x: skirtRect.maxX, y: 0), options: extend)
        context.restoreGState()
        topLight(context, skirt, rect: skirtRect, width: 3, alpha: 0.7, fade: 0.3)
    }

    let faceRect = small ? skirtRect.insetBy(dx: 52, dy: 52).offsetBy(dx: 0, dy: 30)
        : CGRect(x: 268, y: 300, width: 488, height: 468)
    let face = squircle(faceRect, exponent: small ? 3.6 : 4)
    paint(context, face, gradient([hex(0xFFFFFF), hex(0xF4F7F5), hex(0xE3EBE6)], [0, 0.5, 1]),
          top: faceRect.maxY, bottom: faceRect.minY)
    if !small {
        // Dished top: a soft shade under the far lip, light pooling toward the front.
        context.saveGState()
        context.addPath(face)
        context.clip()
        context.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 30 * k, color: hex(0x4C6A5C, 0.32))
        context.addRect(faceRect.insetBy(dx: -80, dy: -80))
        context.addPath(face)
        context.setFillColor(hex(0xFFFFFF))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        // Crisp bevel where the face meets the walls.
        context.saveGState()
        context.addPath(face)
        context.setLineWidth(2.5)
        context.setStrokeColor(hex(0xFFFFFF, 0.9))
        context.strokePath()
        context.restoreGState()
    }

    // The breath ribbon in sage, printed into the face: a fine light edge below it, as if inset.
    let ribbonRect = small
        ? CGRect(x: faceRect.minX + faceRect.width * 0.06, y: faceRect.midY - 170, width: faceRect.width * 0.88, height: 340)
        : CGRect(x: faceRect.minX + faceRect.width * 0.13, y: faceRect.midY - 112, width: faceRect.width * 0.74, height: 224)
    let mark = ribbon(in: ribbonRect, taper: small ? 0.9 : 1.35)
    if !small {
        context.saveGState()
        context.translateBy(x: 0, y: -3)
        context.setFillColor(hex(0xFFFFFF, 0.95))
        context.setStrokeColor(hex(0xFFFFFF, 0.95))
        fillRibbon(context, mark, tip: 10)
        context.restoreGState()
    }
    context.saveGState()
    context.addPath(mark)
    context.setLineWidth(small ? 40 : 10)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.addPath(mark)
    context.clip()
    context.drawLinearGradient(gradient([hex(0x6E9F88), hex(0x4F7F6A), hex(0x426D5A)], [0, 0.55, 1]),
                               start: CGPoint(x: ribbonRect.minX, y: ribbonRect.maxY),
                               end: CGPoint(x: ribbonRect.maxX, y: ribbonRect.minY), options: extend)
    context.restoreGState()
}

/// Template glyph: the keycap as a solid squircle with the ribbon cut out of it.
func drawMenuBarMark(_ context: CGContext, scale: CGFloat, live: Bool) {
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(hex(0x000000))
    context.addPath(squircle(CGRect(x: 2, y: 2, width: 14, height: 14), exponent: 3.6))
    context.fillPath()
    context.setBlendMode(.clear)
    let ribbonRect = CGRect(x: 3.7, y: 4.9, width: 10.6, height: 8.2)
    fillRibbon(context, ribbon(in: ribbonRect, swell: live ? 1.6 : 1, taper: 1.1), tip: 1.2)
}

for (filename, size) in appIconSizes {
    try renderPNG(width: size, height: size, to: appIconURL.appendingPathComponent(filename)) {
        drawAppIcon($0, side: CGFloat(size))
    }
}
for (url, name, live) in [(menuIconURL, "HushKeyMenuBar", false), (liveMenuIconURL, "HushKeyMenuBarLive", true)] {
    for scale in [1, 2] {
        let file = scale == 1 ? "\(name).png" : "\(name)@2x.png"
        try renderPNG(width: 18 * scale, height: 18 * scale, to: url.appendingPathComponent(file)) {
            drawMenuBarMark($0, scale: CGFloat(scale), live: live)
        }
    }
    let contents = """
    {
      "images" : [
        { "filename" : "\(name).png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "\(name)@2x.png", "idiom" : "universal", "scale" : "2x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }

    """
    try contents.write(to: url.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
