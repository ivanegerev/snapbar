import SwiftUI
import AppKit

/// One-time welcome window shown once permission is set up: the shortcut
/// cheatsheet plus the two tricks people otherwise never find.
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func showIfNeeded() {
        guard !Prefs.hasOnboarded, ScreenPermission.granted else { return }
        Prefs.hasOnboarded = true
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "Welcome to SnapBar"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

private struct WelcomeView: View {
    private let shortcuts: [(String, String)] = [
        ("⌃⇧4", "Capture area"),
        ("⌃⇧6", "Capture window"),
        ("⌃⇧3", "Capture full screen"),
        ("⌃⇧5", "Record / stop recording"),
        ("⌃⇧2", "Copy text (OCR)"),
        ("⌃⇧C", "Pick color from screen"),
        ("⌃⇧P", "Pin last screenshot"),
        ("⌃⇧E", "Annotate last screenshot"),
        ("⌃⇧H", "Capture history"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    label("THE SHORTCUTS")
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                        ForEach(0..<((shortcuts.count + 2) / 3), id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { col in
                                    let idx = row * 3 + col
                                    if idx < shortcuts.count {
                                        shortcutChip(shortcuts[idx].0, shortcuts[idx].1)
                                    } else {
                                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("TWO TRICKS WORTH KNOWING")
                    tip("hand.draw", "Drag the floating thumbnail (or any frame in Recent) straight into Slack, Mail, or Figma.")
                    tip("cursorarrow.click.2", "Right-click anything in Recent or History for annotate, pin, copy, and trash.")
                }

                HStack(spacing: 10) {
                    Button {
                        WelcomeWindowController.shared.close()
                        AppServices.shared.captureArea()
                    } label: {
                        Text("TAKE YOUR FIRST SHOT  ⌃⇧4")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Brand.vermillion))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.ink, lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button("Open Settings") {
                        SettingsWindowController.shared.show()
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 560)
        .background(Brand.paper)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Brand.paper)
                Circle().fill(Brand.vermillion).frame(width: 9, height: 9)
            }
            Text("Loaded and ready.")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Brand.paper)
            Text("SNAPBAR LIVES IN YOUR MENU BAR, TOP RIGHT")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Brand.paper.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Brand.ink)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Brand.graphite)
    }

    private func shortcutChip(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Brand.cream))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.hairline, lineWidth: 1))
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Brand.vermillion)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
