import AppKit
import SwiftUI
import CoreGraphics

/// Screen Recording (TCC) permission handling.
///
/// macOS quirks this deals with:
/// - The grant only takes effect after the app relaunches — captures fail
///   silently until then.
/// - Ad-hoc signed builds lose the grant whenever the binary changes, so the
///   system re-prompts after updates.
enum ScreenPermission {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (only works once per TCC state — afterwards the
    /// user must flip the toggle in System Settings).
    static func request() {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Relaunches the app so a fresh grant takes effect.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.6; /usr/bin/open \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Window

final class PermissionWindowController {
    static let shared = PermissionWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "SnapBar Setup"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

// MARK: - View

private struct PermissionView: View {
    @State private var granted = ScreenPermission.granted
    @State private var requestedOnce = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 16) {
                Text("SnapBar drives the same capture engine as ⇧⌘5, so macOS needs one switch flipped: **Screen Recording**. It's a one-time thing — flip it, relaunch, done.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.graphite)
                    .fixedSize(horizontal: false, vertical: true)

                statusRow

                if granted {
                    VStack(spacing: 8) {
                        Button {
                            ScreenPermission.relaunch()
                        } label: {
                            Text("RELAUNCH SNAPBAR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Brand.vermillion))
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.ink, lineWidth: 1))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Text("macOS applies the permission only after a relaunch — one click and you're shooting.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.graphite)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Button("Grant Permission…") {
                                requestedOnce = true
                                ScreenPermission.request()
                                // The system prompt only appears once; the
                                // reliable path is System Settings.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    if !ScreenPermission.granted { ScreenPermission.openSystemSettings() }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.ink)

                            Button("Open System Settings") {
                                ScreenPermission.openSystemSettings()
                            }
                        }
                        Text("Privacy & Security → Screen & System Audio Recording → turn on SnapBar.\nThis window updates by itself once it's granted.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.graphite)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 440)
        .background(Brand.paper)
        .environment(\.colorScheme, .light)
        .onReceive(timer) { _ in granted = ScreenPermission.granted }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Brand.paper)
                Circle().fill(Brand.vermillion).frame(width: 9, height: 9)
            }
            Text("One permission, then you're set")
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(Brand.paper)
            Text("REQUIRED ONCE · SCREEN RECORDING")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Brand.paper.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Brand.ink)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : Brand.vermillion)
            Text("Screen Recording")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Brand.ink)
            Spacer()
            Text(granted ? "GRANTED" : "NOT GRANTED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(granted ? .green : Brand.vermillion)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.cream))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline, lineWidth: 1))
    }
}
