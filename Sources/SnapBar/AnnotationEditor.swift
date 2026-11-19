import SwiftUI
import AppKit
import Combine
import CoreImage

// MARK: - Model

enum AnnoTool: String, CaseIterable, Identifiable {
    case arrow, line, rect, ellipse, highlight, freehand, text, step, redact, pixelate, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .highlight: return "highlighter"
        case .freehand: return "scribble"
        case .text: return "textformat"
        case .step: return "1.circle"
        case .redact: return "rectangle.fill"
        case .pixelate: return "checkerboard.rectangle"
        case .crop: return "crop"
        }
    }

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .highlight: return "Highlighter"
        case .freehand: return "Draw"
        case .text: return "Text"
        case .step: return "Step Number"
        case .redact: return "Redact"
        case .pixelate: return "Pixelate (Pro)"
        case .crop: return "Crop"
        }
    }

    var isProFeature: Bool { self == .pixelate }
}

/// One drawn element. Coordinates are in image point space, top-left origin
/// (matching SwiftUI), converted to bottom-left only at final AppKit render.
struct Annotation: Identifiable {
    let id = UUID()
    var tool: AnnoTool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var color: Color = .red
    var lineWidth: CGFloat = 4
    var text: String = ""
    var number: Int = 0

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

struct BackgroundPreset: Identifiable {
    let id: Int
    let name: String
    let colors: [NSColor]

    // Flat brand fills repeat one colour, because NSGradient needs two stops.
    static let all: [BackgroundPreset] = [
        .init(id: 0, name: "Paper", colors: [Brand.nsPaper, Brand.nsPaper]),
        .init(id: 1, name: "Ink", colors: [Brand.nsInk, Brand.nsInk]),
        .init(id: 2, name: "Vermillion", colors: [Brand.nsVermillion, Brand.nsVermillion]),
        .init(id: 3, name: "Graphite", colors: [NSColor(Brand.graphite), NSColor(Brand.graphite)]),
    ]

    var swiftUIColors: [Color] { colors.map { Color(nsColor: $0) } }
}

final class EditorModel: ObservableObject {
    /// The file Save writes to; Save As and the HEIC/PDF/GIF → .png save move it.
    @Published private(set) var url: URL
    let image: NSImage
    let imageSize: CGSize
    lazy var pixelatedImage: NSImage? = Self.pixelate(image)
    /// Markup that is not in `url` yet; the window asks before closing over it.
    var isDirty = false

    @Published var annotations: [Annotation] = [] { didSet { isDirty = true } }
    @Published var current: Annotation?
    @Published var tool: AnnoTool = .arrow
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 4
    @Published var stepCounter = 1

    @Published var beautifyOn = false { didSet { isDirty = true } }
    @Published var backgroundIndex = 0 { didSet { isDirty = true } }
    @Published var padding: CGFloat = 56 { didSet { isDirty = true } }
    @Published var cornerRadius: CGFloat = 14 { didSet { isDirty = true } }

    /// Non-destructive crop, applied at render time. nil = full image.
    @Published var cropRect: CGRect? { didSet { isDirty = true } }

    // In-progress text annotation being typed.
    @Published var pendingTextAt: CGPoint?
    @Published var textInput = ""

    init?(url: URL) {
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        self.url = url
        self.image = image
        self.imageSize = image.size
    }

    var fontSize: CGFloat { max(14, lineWidth * 6) }

    func undo() {
        guard let last = annotations.popLast() else { return }
        // Undo is LIFO, so a removed step is always the highest number left.
        if last.tool == .step { stepCounter = last.number }
    }

    func clearAll() {
        annotations.removeAll()
        stepCounter = 1
    }

    func commitPendingText() {
        defer { pendingTextAt = nil; textInput = "" }
        guard let at = pendingTextAt, !textInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var a = Annotation(tool: .text, start: at, end: at, color: color, lineWidth: lineWidth)
        a.text = textInput
        annotations.append(a)
    }

    private static func pixelate(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(12, ci.extent.width / 90), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    // MARK: - Final rendering (AppKit, bottom-left origin)

    func renderFinal() -> NSImage {
        let px = image.representations.map(\.pixelsWide).max() ?? 0
        // Vector reps (PDF captures) report 0 pixels; rasterize those at screen scale, not 1x.
        let pxPerPoint = px > 0 ? max(1, CGFloat(px) / imageSize.width) : (NSScreen.main?.backingScaleFactor ?? 2)
        // Crop and padding on whole device pixels, so the image is copied rather than resampled.
        func snap(_ v: CGFloat) -> CGFloat { (v * pxPerPoint).rounded() / pxPerPoint }
        let pad = snap(beautifyOn ? padding : 0)
        let c = cropRect ?? CGRect(origin: .zero, size: imageSize)
        let src = CGRect(x: snap(c.minX), y: snap(c.minY), width: snap(c.maxX) - snap(c.minX), height: snap(c.maxY) - snap(c.minY))
        let outPointSize = CGSize(width: src.width + pad * 2, height: src.height + pad * 2)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((outPointSize.width * pxPerPoint).rounded()),
            pixelsHigh: Int((outPointSize.height * pxPerPoint).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = outPointSize

        NSGraphicsContext.saveGraphicsState()
        let gctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gctx
        let cg = gctx.cgContext

        let imgRect = NSRect(x: pad, y: pad, width: src.width, height: src.height)
        // Source rect within the original image, bottom-left origin (for cropping).
        let srcBL = NSRect(x: src.minX, y: imageSize.height - src.maxY, width: src.width, height: src.height)

        if beautifyOn {
            let preset = BackgroundPreset.all[backgroundIndex % BackgroundPreset.all.count]
            let gradient = NSGradient(colors: preset.colors)!
            gradient.draw(in: NSRect(origin: .zero, size: outPointSize), angle: -60)

            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: imgRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            cg.restoreGState()

            cg.saveGState()
            NSBezierPath(roundedRect: imgRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            image.draw(in: imgRect, from: srcBL, operation: .sourceOver, fraction: 1)
            cg.restoreGState()
        } else {
            image.draw(in: imgRect, from: srcBL, operation: .sourceOver, fraction: 1)
        }

        // Annotations: convert from top-left image space into the padded,
        // crop-relative, bottom-left canvas.
        let h = imageSize.height
        func cv(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - src.minX + pad, y: src.maxY - p.y + pad) }
        func cvRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX - src.minX + pad, y: src.maxY - r.maxY + pad, width: r.width, height: r.height) }

        // Keep markup outside the crop or image off the backdrop, as the preview's clipShape does.
        if beautifyOn { NSBezierPath(roundedRect: imgRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip() }

        for a in annotations {
            let ns = NSColor(a.color)
            switch a.tool {
            case .rect:
                ns.setStroke()
                let p = NSBezierPath(roundedRect: cvRect(a.rect), xRadius: 2, yRadius: 2)
                p.lineWidth = a.lineWidth
                p.stroke()
            case .ellipse:
                ns.setStroke()
                let p = NSBezierPath(ovalIn: cvRect(a.rect))
                p.lineWidth = a.lineWidth
                p.stroke()
            case .line:
                ns.setStroke()
                let p = NSBezierPath()
                p.move(to: cv(a.start)); p.line(to: cv(a.end))
                p.lineWidth = a.lineWidth
                p.lineCapStyle = .round
                p.stroke()
            case .arrow:
                ns.setStroke(); ns.setFill()
                let s = cv(a.start), e = cv(a.end)
                let angle = atan2(e.y - s.y, e.x - s.x)
                let head = max(12, a.lineWidth * 3.5)
                let lineEnd = CGPoint(x: e.x - cos(angle) * head * 0.7, y: e.y - sin(angle) * head * 0.7)
                let p = NSBezierPath()
                p.move(to: s); p.line(to: lineEnd)
                p.lineWidth = a.lineWidth
                p.lineCapStyle = .round
                p.stroke()
                let tip = NSBezierPath()
                tip.move(to: e)
                tip.line(to: CGPoint(x: e.x - cos(angle - 0.45) * head, y: e.y - sin(angle - 0.45) * head))
                tip.line(to: CGPoint(x: e.x - cos(angle + 0.45) * head, y: e.y - sin(angle + 0.45) * head))
                tip.close()
                tip.fill()
            case .highlight, .freehand:
                let isHighlight = a.tool == .highlight
                (isHighlight ? ns.withAlphaComponent(0.4) : ns).setStroke()
                guard a.points.count > 1 else { break }
                let p = NSBezierPath()
                p.move(to: cv(a.points[0]))
                for pt in a.points.dropFirst() { p.line(to: cv(pt)) }
                p.lineWidth = isHighlight ? a.lineWidth * 5 : a.lineWidth
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            case .text:
                let attr = NSAttributedString(string: a.text, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: max(14, a.lineWidth * 6)),
                    .foregroundColor: ns,
                ])
                let size = attr.size()
                let top = cv(a.start)
                attr.draw(at: CGPoint(x: top.x, y: top.y - size.height))
            case .step:
                let r = 12 + a.lineWidth * 2
                let center = cv(a.start)
                ns.setFill()
                NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()
                let attr = NSAttributedString(string: "\(a.number)", attributes: [
                    .font: NSFont.boldSystemFont(ofSize: r * 1.1),
                    .foregroundColor: NSColor.white,
                ])
                let size = attr.size()
                attr.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
            case .redact:
                NSColor.black.setFill()
                NSBezierPath(roundedRect: cvRect(a.rect), xRadius: 2, yRadius: 2).fill()
            case .pixelate:
                guard let pix = pixelatedImage else { break }
                let dest = cvRect(a.rect)
                // Source rect in the pixelated image, bottom-left origin.
                let pixSrc = CGRect(x: a.rect.minX, y: h - a.rect.maxY, width: a.rect.width, height: a.rect.height)
                pix.draw(in: dest, from: pixSrc, operation: .sourceOver, fraction: 1)
            case .crop:
                break // crop is a model property, never stored as an annotation
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let final = NSImage(size: outPointSize)
        final.addRepresentation(rep)
        return final
    }

    func save(to destination: URL? = nil) {
        commitPendingText()
        var target = destination ?? url
        let type: NSBitmapImageRep.FileType
        switch target.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        case "tif", "tiff": type = .tiff
        case "png": type = .png
        default:
            // NSBitmapImageRep can't write HEIC/PDF/GIF: save a sibling .png (never an existing file)
            // instead of putting PNG bytes under the original's name.
            type = .png
            let base = target.deletingPathExtension()
            target = base.appendingPathExtension("png")
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent) \(n).png")
                n += 1
            }
        }
        let rendered = renderFinal()
        guard let tiff = rendered.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: type, properties: [.compressionFactor: 0.92]) else {
            Toast.show("Couldn't save \(target.lastPathComponent)", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        // Not .atomic: that swaps in a new inode and drops Finder tags and the CaptureTag xattr.
        let tmp = Prefs.replacementTempURL(for: target)
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            Toast.show("Couldn't save — \(error.localizedDescription)", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        url = target
        isDirty = false
        Recents.add(target)
        NotificationCenter.default.post(name: AppServices.capturesChanged, object: target)
        Toast.show("Saved \(target.lastPathComponent)")
    }

    func copyToClipboard() {
        commitPendingText()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([renderFinal()])
        Toast.show("Copied to clipboard")
    }
}

// MARK: - View

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var license = LicenseManager.shared
    @FocusState private var textFieldFocused: Bool

    /// nil = fit to window; otherwise an absolute zoom factor (1 = 100%).
    @State private var zoomFactor: CGFloat?
    @State private var fittedScale: CGFloat = 1

    private let swatches: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
    private static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let fit = fitScale(in: geo.size)
                let scale = zoomFactor ?? fit
                let size = CGSize(width: model.imageSize.width * scale, height: model.imageSize.height * scale)
                ScrollView([.horizontal, .vertical]) {
                    // Backdrop, padding and shadow scale with zoom, so the preview frames the image as the saved file does.
                    canvas(displaySize: size)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: model.beautifyOn ? model.cornerRadius * scale : 0))
                        .shadow(color: model.beautifyOn ? .black.opacity(0.45) : .clear, radius: 15 * scale, y: 6 * scale)
                        .padding(model.beautifyOn ? model.padding * scale : 16)
                        .background(model.beautifyOn ? LinearGradient(
                            colors: BackgroundPreset.all[model.backgroundIndex % BackgroundPreset.all.count].swiftUIColors,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ) : nil)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .onAppear { fittedScale = fit }
                .onChange(of: geo.size) { newSize in fittedScale = fitScale(in: newSize) }
            }
            if model.beautifyOn {
                Divider()
                beautifyBar
            }
        }
        .frame(minWidth: 880, minHeight: 500)
    }

    private func fitScale(in container: CGSize) -> CGFloat {
        // Beautify padding scales with the image, so fit both inside a fixed 16pt margin.
        let pad = model.beautifyOn ? model.padding * 2 : 0
        let availW = max(container.width - 32, 100)
        let availH = max(container.height - 32, 100)
        return min(availW / (model.imageSize.width + pad), availH / (model.imageSize.height + pad), 1)
    }

    private var zoomLabel: String {
        guard let z = zoomFactor else { return "FIT" }
        return "\(Int((z * 100).rounded()))%"
    }

    private func zoomStep(_ direction: Int) {
        let current = zoomFactor ?? fittedScale
        if direction > 0 {
            zoomFactor = Self.zoomSteps.first(where: { $0 > current * 1.01 }) ?? Self.zoomSteps.last
        } else {
            zoomFactor = Self.zoomSteps.last(where: { $0 < current * 0.99 }) ?? Self.zoomSteps.first
        }
    }

    // MARK: Canvas

    private func canvas(displaySize: CGSize) -> some View {
        let scale = displaySize.width / model.imageSize.width
        return ZStack(alignment: .topLeading) {
            Image(nsImage: model.image)
                .resizable()
                .interpolation(.high)

            Canvas { ctx, canvasSize in
                for a in model.annotations { draw(a, in: &ctx, scale: scale) }
                if let cur = model.current { draw(cur, in: &ctx, scale: scale) }
                if let crop = model.cropRect {
                    let r = CGRect(
                        x: crop.minX * scale, y: crop.minY * scale,
                        width: crop.width * scale, height: crop.height * scale
                    )
                    var outside = Path(CGRect(origin: .zero, size: canvasSize))
                    outside.addRect(r)
                    ctx.fill(outside, with: .color(.black.opacity(0.4)), style: FillStyle(eoFill: true))
                    ctx.stroke(
                        Path(r),
                        with: .color(Brand.vermillion),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                }
            }
            .allowsHitTesting(false)

            if let at = model.pendingTextAt {
                TextField("Text", text: $model.textInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: max(12, model.fontSize * scale * 0.8), weight: .bold))
                    .frame(width: 220)
                    .offset(x: at.x * scale, y: at.y * scale)
                    .focused($textFieldFocused)
                    .onSubmit { model.commitPendingText() }
                    .onAppear { textFieldFocused = true }
            }
        }
        .contentShape(Rectangle())
        .gesture(drawGesture(scale: scale))
    }

    private func drawGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                let loc = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                switch model.tool {
                case .text, .step:
                    break // placed on tap (gesture end)
                case .freehand, .highlight:
                    if model.current == nil {
                        model.current = Annotation(tool: model.tool, start: start, end: loc, points: [start], color: model.color, lineWidth: model.lineWidth)
                    }
                    model.current?.points.append(loc)
                    model.current?.end = loc
                default:
                    if model.current == nil {
                        model.current = Annotation(tool: model.tool, start: start, end: loc, color: model.color, lineWidth: model.lineWidth)
                    }
                    model.current?.end = loc
                }
            }
            .onEnded { value in
                let loc = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                switch model.tool {
                case .crop:
                    if var cur = model.current {
                        cur.end = loc
                        let rect = cur.rect.intersection(CGRect(origin: .zero, size: model.imageSize))
                        model.cropRect = (rect.width > 8 && rect.height > 8) ? rect : nil
                    }
                    model.current = nil
                case .text:
                    model.commitPendingText()
                    model.pendingTextAt = loc
                case .step:
                    var a = Annotation(tool: .step, start: loc, end: loc, color: model.color, lineWidth: model.lineWidth)
                    a.number = model.stepCounter
                    model.stepCounter += 1
                    model.annotations.append(a)
                default:
                    if var cur = model.current {
                        cur.end = loc
                        // A click without a drag would leave a stray arrow or dot; freehand dots are deliberate.
                        if hypot(cur.end.x - cur.start.x, cur.end.y - cur.start.y) > 2 || cur.tool == .freehand || cur.tool == .highlight {
                            model.annotations.append(cur)
                        }
                    }
                    model.current = nil
                }
            }
    }

    private func draw(_ a: Annotation, in ctx: inout GraphicsContext, scale: CGFloat) {
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }
        let rect = CGRect(
            x: a.rect.minX * scale, y: a.rect.minY * scale,
            width: a.rect.width * scale, height: a.rect.height * scale
        )
        let lw = a.lineWidth * scale

        switch a.tool {
        case .rect:
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(a.color), lineWidth: lw)
        case .ellipse:
            ctx.stroke(Path(ellipseIn: rect), with: .color(a.color), lineWidth: lw)
        case .line:
            var p = Path()
            p.move(to: pt(a.start)); p.addLine(to: pt(a.end))
            ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .arrow:
            let s = pt(a.start), e = pt(a.end)
            let angle = atan2(e.y - s.y, e.x - s.x)
            let head = max(12, a.lineWidth * 3.5) * scale
            var p = Path()
            p.move(to: s)
            p.addLine(to: CGPoint(x: e.x - cos(angle) * head * 0.7, y: e.y - sin(angle) * head * 0.7))
            ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            var tip = Path()
            tip.move(to: e)
            tip.addLine(to: CGPoint(x: e.x - cos(angle - 0.45) * head, y: e.y - sin(angle - 0.45) * head))
            tip.addLine(to: CGPoint(x: e.x - cos(angle + 0.45) * head, y: e.y - sin(angle + 0.45) * head))
            tip.closeSubpath()
            ctx.fill(tip, with: .color(a.color))
        case .highlight, .freehand:
            guard a.points.count > 1 else { break }
            var p = Path()
            p.move(to: pt(a.points[0]))
            for point in a.points.dropFirst() { p.addLine(to: pt(point)) }
            let isHighlight = a.tool == .highlight
            ctx.stroke(
                p,
                with: .color(isHighlight ? a.color.opacity(0.4) : a.color),
                style: StrokeStyle(lineWidth: isHighlight ? lw * 5 : lw, lineCap: .round, lineJoin: .round)
            )
        case .text:
            ctx.draw(
                Text(a.text)
                    .font(.system(size: max(14, a.lineWidth * 6) * scale, weight: .bold))
                    .foregroundColor(a.color),
                at: pt(a.start),
                anchor: .topLeading
            )
        case .step:
            let r = (12 + a.lineWidth * 2) * scale
            let c = pt(a.start)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(a.color))
            ctx.draw(
                Text("\(a.number)").font(.system(size: r * 1.1, weight: .bold)).foregroundColor(.white),
                at: c, anchor: .center
            )
        case .redact:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.black))
        case .pixelate:
            guard let pix = model.pixelatedImage else { break }
            var clipped = ctx
            clipped.clip(to: Path(rect))
            clipped.draw(
                Image(nsImage: pix),
                in: CGRect(origin: .zero, size: CGSize(width: model.imageSize.width * scale, height: model.imageSize.height * scale))
            )
        case .crop:
            // Live crop drag preview; the committed crop is drawn by the canvas.
            ctx.stroke(
                Path(rect),
                with: .color(Brand.vermillion),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Scrolls instead of clipping when the window is narrower than the tools; the actions stay pinned.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(AnnoTool.allCases) { tool in
                            toolButton(tool)
                        }
                    }
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                    Divider().frame(height: 20)

                    HStack(spacing: 5) {
                        ForEach(swatches, id: \.self) { swatch in
                            Button { model.color = swatch } label: {
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 15, height: 15)
                                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                                    .overlay(
                                        Circle().strokeBorder(Brand.vermillion, lineWidth: model.color == swatch ? 2 : 0).padding(-3)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(swatch.description.capitalized)
                            .accessibilityAddTraits(model.color == swatch ? .isSelected : [])
                        }
                    }

                    Slider(value: $model.lineWidth, in: 1...12)
                        .frame(width: 80)
                        .help("Stroke width")

                    Divider().frame(height: 20)

                    Button {
                        if !license.isPro {
                            UpgradeWindowController.shared.show()
                        } else {
                            model.beautifyOn.toggle()
                        }
                    } label: {
                        Label(license.isPro ? "Beautify" : "Beautify (Pro)", systemImage: "photo.artframe")
                    }
                    .buttonStyle(.bordered)
                    .tint(model.beautifyOn ? Brand.vermillion : nil)

                    if let crop = model.cropRect {
                        Button {
                            model.cropRect = nil
                        } label: {
                            Label("\(Int(crop.width))×\(Int(crop.height))", systemImage: "xmark")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.vermillion)
                        .help("Crop applied on save — click to clear")
                    }

                    Divider().frame(height: 20)

                    HStack(spacing: 3) {
                        Button {
                            zoomStep(-1)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .keyboardShortcut("-", modifiers: .command)
                        .help("Zoom out (⌘−)")

                        Text(zoomLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .frame(width: 36)

                        Button {
                            zoomStep(1)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .keyboardShortcut("=", modifiers: .command)
                        .help("Zoom in (⌘+)")

                        Button("Fit") {
                            zoomFactor = nil
                        }
                        .keyboardShortcut("0", modifiers: .command)
                        .help("Fit to window (⌘0)")
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            // While text is being typed, ⌘Z belongs to the text field (Edit menu undo:).
            .keyboardShortcut(model.pendingTextAt == nil ? KeyboardShortcut("z", modifiers: .command) : nil)
            .help("Undo")
            .disabled(model.annotations.isEmpty)

            Button("Copy") { model.copyToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)

            Menu {
                Button("Save As…") { saveAs() }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolButton(_ tool: AnnoTool) -> some View {
        Button {
            if tool.isProFeature && !license.isPro {
                UpgradeWindowController.shared.show()
                return
            }
            model.commitPendingText()
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.tool == tool ? Brand.vermillion.opacity(0.85) : .clear)
                )
                .foregroundStyle(model.tool == tool ? .white : .primary)
                .overlay(alignment: .topTrailing) {
                    if tool.isProFeature && !license.isPro {
                        Image(systemName: "lock.fill").font(.system(size: 7)).offset(x: 2, y: -1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(tool.label)
    }

    private var beautifyBar: some View {
        HStack(spacing: 14) {
            Text("Background").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(BackgroundPreset.all) { preset in
                    Button { model.backgroundIndex = preset.id } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: preset.swiftUIColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Brand.vermillion, lineWidth: model.backgroundIndex == preset.id ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .accessibilityLabel("\(preset.name) background")
                    .accessibilityAddTraits(model.backgroundIndex == preset.id ? .isSelected : [])
                }
            }
            Divider().frame(height: 18)
            Text("Padding").font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.padding, in: 16...160).frame(width: 110)
            Text("Corners").font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.cornerRadius, in: 0...40).frame(width: 90)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func saveAs() {
        let panel = NSSavePanel()
        let base = model.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(base) edited.png"
        panel.directoryURL = Prefs.saveDirURL
        if panel.runModal() == .OK, let dest = panel.url {
            model.save(to: dest)
        }
    }
}

// MARK: - Window controller

enum EditorWindowController {
    /// Open editors. NSWindow.delegate is weak, so this keeps each delegate (and its window) alive.
    private static var windows: [Delegate] = []

    /// Asks before closing over unsaved markup, keeps the title on the file Save writes to,
    /// and forgets the window once it closes.
    private final class Delegate: NSObject, NSWindowDelegate {
        let window: NSWindow
        let model: EditorModel
        private var titleSub: AnyCancellable?

        init(window: NSWindow, model: EditorModel) {
            self.window = window
            self.model = model
            super.init()
            titleSub = model.$url.sink { [weak window] in window?.title = "Edit — \($0.lastPathComponent)" }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model.commitPendingText()
            guard model.isDirty else { return true }
            let alert = NSAlert()
            alert.messageText = "Save changes to “\(model.url.lastPathComponent)”?"
            alert.informativeText = "Your markup will be lost if you don't save it."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { [model] response in
                switch response {
                case .alertFirstButtonReturn:
                    model.save()
                    if !model.isDirty { sender.close() } // a failed save keeps the window open
                case .alertSecondButtonReturn:
                    sender.close()
                default:
                    break
                }
            }
            return false
        }

        func windowWillClose(_ notification: Notification) {
            windows.removeAll { $0 === self }
        }
    }

    /// Quit never calls windowShouldClose, so before terminating put each dirty editor's
    /// Save sheet up instead. Returns true if any editor still has unsaved markup.
    static func closeDirtyForQuit() -> Bool {
        let dirty = windows.filter { $0.model.commitPendingText(); return $0.model.isDirty }
        dirty.forEach { $0.window.performClose(nil) }
        return !dirty.isEmpty
    }

    static func open(_ url: URL) {
        guard let model = EditorModel(url: url) else {
            Toast.show("Can't edit this file", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        let hosting = NSHostingController(rootView: EditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1200, height: 640))
        window.isReleasedWhenClosed = false
        window.center()
        let delegate = Delegate(window: window, model: model)
        window.delegate = delegate
        windows.append(delegate)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
