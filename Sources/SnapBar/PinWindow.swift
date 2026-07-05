import AppKit
import SwiftUI

/// "Pin to screen": a screenshot floats above all windows as a reference.
/// Drag anywhere to move, double-click (or the ✕ on hover) to close.
final class PinWindow: NSPanel {
    private static var pins: [PinWindow] = []

    static func show(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            Toast.show("Only images can be pinned", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        let pin = PinWindow(image: image, url: url)
        pins.append(pin)
        pin.orderFrontRegardless()
    }

    private init(image: NSImage, url: URL) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var size = image.size
        let maxW = screen.width * 0.55
        let maxH = screen.height * 0.55
        let scale = min(maxW / max(size.width, 1), maxH / max(size.height, 1), 1)
        size = NSSize(width: size.width * scale, height: size.height * scale)

        // Cascade pins slightly so several don't stack exactly.
        let offset = CGFloat(Self.pins.count % 5) * 24
        let rect = NSRect(
            x: screen.midX - size.width / 2 + offset,
            y: screen.midY - size.height / 2 - offset,
            width: size.width,
            height: size.height
        )

        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let root = PinView(
            image: image,
            onClose: { [weak self] in self?.closePin() },
            onCopy: {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                Toast.show("Image copied")
            },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            onOpacity: { [weak self] value in self?.animator().alphaValue = value }
        )
        contentView = NSHostingView(rootView: root)
    }

    private func closePin() {
        Self.pins.removeAll { $0 === self }
        close()
    }
}

private struct PinView: View {
    let image: NSImage
    let onClose: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onOpacity: (CGFloat) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1))

            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onClose)
        .contextMenu {
            Button("Copy Image", action: onCopy)
            Button("Reveal in Finder", action: onReveal)
            Menu("Opacity") {
                Button("100%") { onOpacity(1.0) }
                Button("75%") { onOpacity(0.75) }
                Button("50%") { onOpacity(0.5) }
                Button("25%") { onOpacity(0.25) }
            }
            Divider()
            Button("Close Pin", action: onClose)
        }
    }
}
