// Draws the Wakeful app icon and writes every size the asset catalog needs.
//   swift scripts/make-icon.swift Wakeful/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func drawIcon(in ctx: CGContext) {
    // Canvas is 1024×1024, y grows upwards. macOS icon grid: 824pt body, 100pt margin.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1B1A45))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Night-sky background.
    ctx.drawLinearGradient(
        gradient([color(0x3B35A0), color(0x221F63), color(0x0F0E2E)], [0, 0.55, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
    )
    // Warm glow behind the cup.
    ctx.drawRadialGradient(
        gradient([color(0xFF9F43, 0.55), color(0xFF9F43, 0)]),
        startCenter: CGPoint(x: 500, y: 430), startRadius: 0,
        endCenter: CGPoint(x: 500, y: 430), endRadius: 420, options: []
    )

    // Tiny stars.
    for (x, y, r) in [(210.0, 790.0, 7.0), (300, 860, 5), (760, 860, 6), (840, 700, 4), (180, 620, 4), (650, 800, 4)] {
        ctx.setFillColor(color(0xFFFFFF, 0.75))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Saucer.
    let saucer = CGRect(x: 230, y: 228, width: 560, height: 92)
    ctx.setFillColor(color(0xB9B6D9))
    ctx.fillEllipse(in: saucer)
    ctx.setFillColor(color(0xE4E2F5))
    ctx.fillEllipse(in: saucer.insetBy(dx: 18, dy: 10).offsetBy(dx: 0, dy: 8))

    // Handle.
    ctx.setLineWidth(44)
    ctx.setStrokeColor(color(0xF2F0FF))
    ctx.addEllipse(in: CGRect(x: 620, y: 390, width: 150, height: 150))
    ctx.strokePath()

    // Cup body.
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: 300, y: 600))
    cup.addLine(to: CGPoint(x: 700, y: 600))
    cup.addCurve(to: CGPoint(x: 600, y: 290), control1: CGPoint(x: 700, y: 430), control2: CGPoint(x: 675, y: 300))
    cup.addLine(to: CGPoint(x: 400, y: 290))
    cup.addCurve(to: CGPoint(x: 300, y: 600), control1: CGPoint(x: 325, y: 300), control2: CGPoint(x: 300, y: 430))
    cup.closeSubpath()
    ctx.saveGState()
    ctx.addPath(cup)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xFFFFFF), color(0xD9D6F0)]),
        start: CGPoint(x: 330, y: 600), end: CGPoint(x: 700, y: 300), options: []
    )
    ctx.restoreGState()

    // Coffee surface.
    let rim = CGRect(x: 300, y: 562, width: 400, height: 76)
    ctx.setFillColor(color(0xF2F0FF))
    ctx.fillEllipse(in: rim)
    ctx.saveGState()
    ctx.addEllipse(in: rim.insetBy(dx: 22, dy: 12))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xC8742A), color(0x6B3410)]),
        start: CGPoint(x: 320, y: 620), end: CGPoint(x: 690, y: 575), options: []
    )
    ctx.restoreGState()

    // Steam, drawn as glowing S-curves.
    ctx.setLineCap(.round)
    for (index, x) in [430.0, 530.0].enumerated() {
        let steam = CGMutablePath()
        let base = 660.0 + Double(index) * 10
        steam.move(to: CGPoint(x: x, y: base))
        steam.addCurve(to: CGPoint(x: x + 10, y: base + 110), control1: CGPoint(x: x - 50, y: base + 40), control2: CGPoint(x: x + 60, y: base + 60))
        steam.addCurve(to: CGPoint(x: x - 5, y: base + 200), control1: CGPoint(x: x - 40, y: base + 150), control2: CGPoint(x: x + 30, y: base + 170))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 24, color: color(0xFFB347, 0.9))
        ctx.setLineWidth(34)
        ctx.setStrokeColor(color(0xFFC46B))
        ctx.addPath(steam)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Sparkle (the "smart" part: AI agents and automation).
    let center = CGPoint(x: 720, y: 760)
    let sparkle = CGMutablePath()
    let outer = 78.0, inner = 16.0
    for i in 0..<8 {
        let angle = Double(i) * .pi / 4 + .pi / 2
        let radius = i.isMultiple(of: 2) ? outer : inner
        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if i == 0 { sparkle.move(to: point) } else { sparkle.addLine(to: point) }
    }
    sparkle.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0xFFE08A, 0.95))
    ctx.setFillColor(color(0xFFE7A3))
    ctx.addPath(sparkle)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()

    // Subtle inner edge highlight.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.strokePath()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(size: pixels).write(to: output.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: output.appending(path: "Contents.json"))
try! render(size: 1024).write(to: output.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "store/icon-1024.png"))
print("Icon written to \(output.path)")
