// Draws the Tapusin-Tapusin app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle with soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor(white: 0.11, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite gradient with a faint pink/violet glow, echoing the design studies.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1).cgColor,
        NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0.75, green: 0.55, blue: 1.0, alpha: 0.28).cgColor,
        NSColor(red: 0.75, green: 0.55, blue: 1.0, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 820, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 820, y: 860), endRadius: 520, options: [])
    let pink = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 1.0, green: 0.55, blue: 0.70, alpha: 0.16).cgColor,
        NSColor(red: 1.0, green: 0.55, blue: 0.70, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(pink, startCenter: CGPoint(x: 180, y: 160), startRadius: 0,
                           endCenter: CGPoint(x: 180, y: 160), endRadius: 460, options: [])
    // Top edge highlight.
    ctx.addPath(tilePath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    let green = NSColor(red: 0.30, green: 0.75, blue: 0.48, alpha: 1).cgColor
    let amber = NSColor(red: 0.98, green: 0.70, blue: 0.25, alpha: 1).cgColor
    let ring: CGFloat = 62, stroke: CGFloat = 18
    let cx: CGFloat = 300

    func bar(y: CGFloat, to x2: CGFloat, alpha: CGFloat) {
        let r = CGRect(x: 412, y: y - 22, width: x2 - 412, height: 44)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
    }

    // Row 1: done.
    let y1: CGFloat = 660
    ctx.setFillColor(green)
    ctx.fillEllipse(in: CGRect(x: cx - ring, y: y1 - ring, width: ring * 2, height: ring * 2))
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(17)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: cx - 28, y: y1 + 2))
    ctx.addLine(to: CGPoint(x: cx - 8, y: y1 - 20))
    ctx.addLine(to: CGPoint(x: cx + 30, y: y1 + 24))
    ctx.strokePath()
    bar(y: y1, to: 760, alpha: 0.92)

    // Row 2: in progress (ring + right half filled).
    let y2: CGFloat = 512
    ctx.setStrokeColor(amber)
    ctx.setLineWidth(stroke)
    ctx.strokeEllipse(in: CGRect(x: cx - ring + stroke / 2, y: y2 - ring + stroke / 2,
                                 width: (ring - stroke / 2) * 2, height: (ring - stroke / 2) * 2))
    ctx.setFillColor(amber)
    ctx.move(to: CGPoint(x: cx, y: y2))
    ctx.addArc(center: CGPoint(x: cx, y: y2), radius: ring - stroke - 9,
               startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    ctx.closePath()
    ctx.fillPath()
    bar(y: y2, to: 700, alpha: 0.7)

    // Row 3: to do.
    let y3: CGFloat = 364
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    ctx.setLineWidth(stroke)
    ctx.strokeEllipse(in: CGRect(x: cx - ring + stroke / 2, y: y3 - ring + stroke / 2,
                                 width: (ring - stroke / 2) * 2, height: (ring - stroke / 2) * 2))
    bar(y: y3, to: 620, alpha: 0.42)
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.imageInterpolation = .high
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: root.appendingPathComponent("build/AppIcon-preview.png"))
print("Wrote \(iconset.path)")
