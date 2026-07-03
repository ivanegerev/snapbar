// Renders the SnapBar app icon — the "Contact Sheet" mark: viewfinder
// crop-corner brackets and a vermillion keeper dot on a paper squircle.
// Usage: swift make-icon.swift <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: swift make-icon.swift <output.iconset>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let paper = NSColor(red: 0.949, green: 0.933, blue: 0.890, alpha: 1)
let ink = NSColor(red: 0.102, green: 0.090, blue: 0.075, alpha: 1)
let vermillion = NSColor(red: 0.882, green: 0.306, blue: 0.114, alpha: 1)

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // macOS icon grid: content sits inside ~10% margins
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    paper.setFill()
    squircle.fill()

    // faint printed edge
    ink.withAlphaComponent(0.12).setStroke()
    squircle.lineWidth = max(1, s * 0.006)
    squircle.stroke()

    // Viewfinder brackets
    let frame = rect.insetBy(dx: rect.width * 0.235, dy: rect.height * 0.235)
    let arm = frame.width * 0.34
    let stroke = max(1.5, rect.width * 0.062)

    ink.setStroke()
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        // (arm end A, corner, arm end B)
        (CGPoint(x: frame.minX, y: frame.maxY - arm), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX + arm, y: frame.maxY)),
        (CGPoint(x: frame.maxX - arm, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY - arm)),
        (CGPoint(x: frame.maxX, y: frame.minY + arm), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX - arm, y: frame.minY)),
        (CGPoint(x: frame.minX + arm, y: frame.minY), CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.minY + arm)),
    ]
    for (a, corner, b) in corners {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: corner)
        p.line(to: b)
        p.lineWidth = stroke
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    // The keeper dot
    let r = rect.width * 0.088
    vermillion.setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in entries {
    let rep = renderIcon(pixels: entry.pixels)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: outDir.appendingPathComponent("\(entry.name).png"))
}
print("iconset written to \(outDir.path)")
