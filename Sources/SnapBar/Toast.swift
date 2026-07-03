import AppKit
import SwiftUI

/// Small HUD notification shown top-center of the screen ("Copied 214 characters").
enum Toast {
    private static var panel: NSPanel?

    static func show(_ message: String, symbol: String = "checkmark.circle.fill", tint: Color = .green) {
        panel?.close()
        panel = nil

        let view = NSHostingView(rootView: ToastView(message: message, symbol: symbol, tint: tint))
        view.frame.size = view.fittingSize

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = view.frame.size
        let rect = NSRect(
            x: screen.midX - size.width / 2,
            y: screen.maxY - size.height - 28,
            width: size.width,
            height: size.height
        )

        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = view
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak p] in
            guard let p, p === panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.close()
                if panel === p { panel = nil }
            })
        }
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
    }
}
