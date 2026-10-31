// Draws the app icon: swift scripts/make-icon.swift  (writes the PNGs into the asset catalog)
import AppKit

let out = "Sources/MDEdit/Assets.xcassets/AppIcon.appiconset"
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill(); path.fill()
    NSColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1).setStroke(); path.lineWidth = max(1, s * 0.008); path.stroke()
    // "M" and a down arrow: Markdown's own mark
    let blue = NSColor(srgbRed: 0.204, green: 0.471, blue: 0.965, alpha: 1)
    let font = NSFont.monospacedSystemFont(ofSize: s * 0.40, weight: .semibold)
    let m = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1)])
    let ms = m.size()
    m.draw(at: NSPoint(x: s * 0.5 - ms.width * 0.82, y: s * 0.5 - ms.height * 0.5))
    let a = NSBezierPath()
    let ax = s * 0.70, top = s * 0.62, bottom = s * 0.38
    a.move(to: NSPoint(x: ax, y: top)); a.line(to: NSPoint(x: ax, y: bottom))
    a.move(to: NSPoint(x: ax - s * 0.075, y: bottom + s * 0.075)); a.line(to: NSPoint(x: ax, y: bottom)); a.line(to: NSPoint(x: ax + s * 0.075, y: bottom + s * 0.075))
    a.lineWidth = s * 0.05; a.lineCapStyle = .round; a.lineJoinStyle = .round
    blue.setStroke(); a.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for (pt, scale) in sizes {
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! draw(pt * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    images.append("{\"filename\":\"\(name)\",\"idiom\":\"mac\",\"scale\":\"\(scale)x\",\"size\":\"\(pt)x\(pt)\"}")
}
try! "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(toFile: "\(out)/Contents.json", atomically: true, encoding: .utf8)
try! "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(toFile: "Sources/MDEdit/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)
