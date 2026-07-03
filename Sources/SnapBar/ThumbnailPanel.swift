import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating thumbnail shown bottom-right after a capture. Click opens the file,
/// drag it into another app, and hovering reveals quick actions
/// (Annotate / Pin / Copy). Hover pauses auto-dismiss.
final class ThumbnailPanel: NSPanel {
    private static var current: ThumbnailPanel?

    static func show(for url: URL, services: AppServices) {
        current?.close()
        let panel = ThumbnailPanel(url: url, services: services)
        current = panel
        panel.orderFrontRegardless()
        panel.scheduleDismiss(after: 7)
    }

    private var dismissTimer: Timer?

    private init(url: URL, services: AppServices) {
        let isMovie = url.pathExtension.lowercased() == "mov"
        let image = NSImage(contentsOf: url)

        let maxSide: CGFloat = 280
        var size = image?.size ?? NSSize(width: 180, height: 120)
        if size.width <= 0 || size.height <= 0 { size = NSSize(width: 180, height: 120) }
        let scale = min(maxSide / max(size.width, size.height), 1)
        let thumbSize = NSSize(width: max(size.width * scale, 120), height: max(size.height * scale, 80))

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let margin: CGFloat = 16
        let frame = NSRect(
            x: screen.maxX - thumbSize.width - margin,
            y: screen.minY + margin,
            width: thumbSize.width,
            height: thumbSize.height
        )

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let root = ThumbnailView(
            url: url,
            image: image,
            isMovie: isMovie,
            onOpen: { [weak self] in
                NSWorkspace.shared.open(url)
                self?.dismiss()
            },
            onAnnotate: { [weak self] in
                self?.dismiss()
                services.annotate(url)
            },
            onPin: { [weak self] in
                self?.dismiss()
                services.pin(url)
            },
            onCopy: { services.copyImage(url) },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.dismissTimer?.invalidate()
                } else {
                    self?.scheduleDismiss(after: 2)
                }
            }
        )
        contentView = NSHostingView(rootView: root)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
            if ThumbnailPanel.current === self { ThumbnailPanel.current = nil }
        })
    }
}

private struct ThumbnailView: View {
    let url: URL
    let image: NSImage?
    let isMovie: Bool
    let onOpen: () -> Void
    let onAnnotate: () -> Void
    let onPin: () -> Void
    let onCopy: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        VStack(spacing: 6) {
                            Image(systemName: isMovie ? "film" : "photo")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hovering {
                HStack(spacing: 10) {
                    if !isMovie {
                        ActionButton(symbol: "pencil.tip", help: "Annotate", action: onAnnotate)
                        ActionButton(symbol: "pin", help: "Pin to screen", action: onPin)
                    }
                    ActionButton(symbol: "doc.on.doc", help: "Copy", action: onCopy)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1))
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
            onHoverChange(h)
        }
        .onTapGesture(perform: onOpen)
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}

private struct ActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
