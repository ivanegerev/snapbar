import SwiftUI
import AppKit

/// Branded About panel — paper, serif, and the keeper dot.
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "About SnapBar"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "V\(short) · BUILD \(build)"
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.cream)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
                Image(systemName: "viewfinder")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Brand.ink)
                Circle().fill(Brand.vermillion).frame(width: 11, height: 11)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("SnapBar")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(Brand.ink)
                Text(version)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Brand.graphite)
            }

            Text("Shoot your screen like it's film.")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(Brand.graphite)

            Rectangle().fill(Brand.hairline).frame(width: 180, height: 1)

            HStack(spacing: 16) {
                link("Website", url: "https://ivanegerev.github.io/snapbar/")
                link("Source", url: "https://github.com/ivanegerev/snapbar")
                link("Support", url: "mailto:ivanegerev@icloud.com")
            }

            Text("© 2026 IVAN EGEREV · NO CLOUD · NO ACCOUNT")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Brand.graphite.opacity(0.7))
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(width: 340)
        .background(Brand.paper)
        .environment(\.colorScheme, .light)
    }

    private func link(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Brand.ink)
                .underline(color: Brand.vermillion)
        }
    }
}
