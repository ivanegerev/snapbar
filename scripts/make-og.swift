// Renders the 1200×630 Open Graph card for the website.
// Usage: swift make-og.swift <output.png>
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift make-og.swift <output.png>\n", stderr)
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])

let paper = NSColor(red: 0.949, green: 0.933, blue: 0.890, alpha: 1)
let ink = NSColor(red: 0.102, green: 0.090, blue: 0.075, alpha: 1)
let graphite = NSColor(red: 0.420, green: 0.396, blue: 0.345, alpha: 1)
let vermillion = NSColor(red: 0.882, green: 0.306, blue: 0.114, alpha: 1)

let W = 1200, H = 630
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

paper.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// hairline frame + crop marks
ink.withAlphaComponent(0.25).setStroke()
let frame = NSRect(x: 36, y: 36, width: W - 72, height: H - 72)
let framePath = NSBezierPath(rect: frame)
framePath.lineWidth = 2
framePath.stroke()

// the mark
let markFrame = NSRect(x: 96, y: 356, width: 150, height: 150)
let arm = markFrame.width * 0.32
ink.setStroke()
for (a, c, b) in [
    (NSPoint(x: markFrame.minX, y: markFrame.maxY - arm), NSPoint(x: markFrame.minX, y: markFrame.maxY), NSPoint(x: markFrame.minX + arm, y: markFrame.maxY)),
    (NSPoint(x: markFrame.maxX - arm, y: markFrame.maxY), NSPoint(x: markFrame.maxX, y: markFrame.maxY), NSPoint(x: markFrame.maxX, y: markFrame.maxY - arm)),
    (NSPoint(x: markFrame.maxX, y: markFrame.minY + arm), NSPoint(x: markFrame.maxX, y: markFrame.minY), NSPoint(x: markFrame.maxX - arm, y: markFrame.minY)),
    (NSPoint(x: markFrame.minX + arm, y: markFrame.minY), NSPoint(x: markFrame.minX, y: markFrame.minY), NSPoint(x: markFrame.minX, y: markFrame.minY + arm)),
] {
    let p = NSBezierPath()
    p.move(to: a); p.line(to: c); p.line(to: b)
    p.lineWidth = 13
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    p.stroke()
}
vermillion.setFill()
let r: CGFloat = 15
NSBezierPath(ovalIn: NSRect(x: markFrame.midX - r, y: markFrame.midY - r, width: r * 2, height: r * 2)).fill()

func draw(_ text: String, font: NSFont, color: NSColor, at point: NSPoint, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        .draw(at: point)
}

let serif = NSFont.systemFont(ofSize: 120, weight: .semibold)
let serifDesc = serif.fontDescriptor.withDesign(.serif) ?? serif.fontDescriptor
let display = NSFont(descriptor: serifDesc, size: 120) ?? serif

let serifSmallDesc = NSFont.systemFont(ofSize: 44, weight: .medium).fontDescriptor
    .withDesign(.serif) ?? NSFont.systemFont(ofSize: 44).fontDescriptor
let tagline = NSFont(descriptor: serifSmallDesc.withSymbolicTraits(.italic), size: 44)
    ?? NSFont.systemFont(ofSize: 44)

draw("SnapBar", font: display, color: ink, at: NSPoint(x: 92, y: 200))
draw("Shoot your screen like it's film.", font: tagline, color: graphite, at: NSPoint(x: 98, y: 130))
draw("SB-14 · CAPTURE · RECORD · OCR · PIN · BEAUTIFY · MACOS 13+",
     font: NSFont.monospacedSystemFont(ofSize: 21, weight: .medium),
     color: vermillion, at: NSPoint(x: 98, y: 66), kern: 3)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("og card written to \(out.path)")
