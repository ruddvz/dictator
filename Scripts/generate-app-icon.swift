import AppKit
import Foundation

// Draws HushKey's app icon and menu bar glyph: the breath ribbon from `BreathRibbon` and
// `MorphIcon`, in sage `signal` on a fog squircle. Colours are the Fog & sage tokens from
// docs/DESIGN_SYSTEM.md. Run from the repository root; package-app.sh runs it.

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

/// Superellipse close to the macOS icon squircle.
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

/// The breath ribbon: a lens tapered at both ends whose spine makes one soft S, like the hush
/// in `MorphIcon`. `amplitude` sets the S, `thickness` the half-width at the middle, and
/// `taper` how fine the tips run.
func ribbon(in rect: CGRect, amplitude: CGFloat = 0.22, thickness: CGFloat = 0.27, taper: CGFloat = 1.3) -> CGPath {
    let samples = 160
    var top: [CGPoint] = [], bottom: [CGPoint] = []
    for index in 0...samples {
        let u = CGFloat(index) / CGFloat(samples)
        let x = rect.minX + u * rect.width
        let spine = rect.midY + rect.height * amplitude * sin(2 * .pi * u)
        let half = rect.height * thickness * pow(sin(.pi * u), taper)
        top.append(CGPoint(x: x, y: spine + half))
        bottom.append(CGPoint(x: x, y: spine - half))
    }
    let path = CGMutablePath()
    path.addLines(between: top + bottom.reversed())
    path.closeSubpath()
    return path
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
    context.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: hex(0x000000, 0.28))
    context.addPath(body)
    context.setFillColor(hex(0xEEF0EE))
    context.fillPath()
    context.restoreGState()

    // Fog: `sheet` at the top settling into `selection` at the bottom, with a faint sage
    // breath of light behind the ribbon.
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(gradient([hex(0xFFFFFF), hex(0xF2F5F3), hex(0xDCE5DF)], [0, 0.5, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: extend)
    context.drawRadialGradient(gradient([hex(0x7FB39C, 0.16), hex(0x7FB39C, 0)], [0, 1]),
                               startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 470), endRadius: 400, options: [])
    context.restoreGState()
    if !small {
        // Edge: a white lip along the top, a faint fog line along the bottom so the light
        // icon keeps its outline on a light Dock.
        context.saveGState()
        context.addPath(body)
        context.clip()
        context.addPath(body)
        context.setLineWidth(8)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(gradient([hex(0xFFFFFF, 1), hex(0xFFFFFF, 0), hex(0x66706B, 0), hex(0x66706B, 0.22)],
                                            [0, 0.3, 0.6, 1]),
                                   start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: extend)
        context.restoreGState()
    }

    // The ribbon, in sage from a lit upper left to a deeper lower right.
    let ribbonRect = small ? CGRect(x: 170, y: 320, width: 684, height: 384) : CGRect(x: 200, y: 352, width: 624, height: 320)
    let mark = ribbon(in: ribbonRect, thickness: small ? 0.31 : 0.27, taper: small ? 1.0 : 1.3)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16 * k), blur: 34 * k, color: hex(0x2F5244, 0.28))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(mark)
    context.clip()
    context.drawLinearGradient(gradient([hex(0x8CC0A8), hex(0x5E9079), hex(0x4F7F6A), hex(0x3B6553)], [0, 0.35, 0.65, 1]),
                               start: CGPoint(x: ribbonRect.minX, y: ribbonRect.maxY),
                               end: CGPoint(x: ribbonRect.maxX, y: ribbonRect.minY), options: extend)
    if !small {
        // A soft sheen across the upper half, so the ribbon reads as a curved surface.
        context.drawLinearGradient(gradient([hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0)], [0, 1]),
                                   start: CGPoint(x: 512, y: ribbonRect.maxY), end: CGPoint(x: 512, y: ribbonRect.midY),
                                   options: [])
    }
    context.endTransparencyLayer()
    context.restoreGState()
}

/// Template glyph: the app icon's ribbon at the same proportions (624 × 320), 17 pt wide on an
/// 18 pt canvas. While dictating it opens into a fuller lens.
func drawMenuBarMark(_ context: CGContext, live: Bool) {
    let height: CGFloat = 17 * 320 / 624
    let rect = CGRect(x: 0.5, y: 9 - height / 2, width: 17, height: height)
    context.setFillColor(hex(0x000000))
    context.addPath(live ? ribbon(in: rect, amplitude: 0.16, thickness: 0.38, taper: 1)
                         : ribbon(in: rect))
    context.fillPath()
}

for (filename, size) in appIconSizes {
    try renderPNG(width: size, height: size, to: appIconURL.appendingPathComponent(filename)) {
        drawAppIcon($0, side: CGFloat(size))
    }
}
// The glyphs are vector PDFs, so the menu bar and the larger sidebar brand row both draw them crisply.
for (url, name, live) in [(menuIconURL, "HushKeyMenuBar", false), (liveMenuIconURL, "HushKeyMenuBarLive", true)] {
    for old in ["\(name).png", "\(name)@2x.png"] {
        try? FileManager.default.removeItem(at: url.appendingPathComponent(old))
    }
    var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
    let data = NSMutableData()
    let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &mediaBox, nil)!
    pdf.beginPDFPage(nil)
    drawMenuBarMark(pdf, live: live)
    pdf.endPDFPage()
    pdf.closePDF()
    // Quartz stamps each PDF with dates and an ID; rewrite only when the drawing changed, so
    // packaging leaves the asset catalog clean.
    let pdfURL = url.appendingPathComponent("\(name).pdf")
    func drawing(_ pdf: Data) -> String {
        String(decoding: pdf, as: UTF8.self)
            .replacingOccurrences(of: #"/(CreationDate|ModDate)\s*\([^)]*\)|/ID\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
    }
    if (try? Data(contentsOf: pdfURL)).map(drawing) != drawing(data as Data) {
        try (data as Data).write(to: pdfURL, options: .atomic)
    }
    let contents = """
    {
      "images" : [
        { "filename" : "\(name).pdf", "idiom" : "universal" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
    }

    """
    try contents.write(to: url.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
