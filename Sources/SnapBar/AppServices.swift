import AppKit
import Combine
import ImageIO

/// Central hub the UI talks to: owns the capture engine, publishes state for
/// SwiftUI, and hosts the actions shared by the popover, hotkeys and thumbnails.
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let capture = CaptureManager()

    @Published private(set) var isRecording = false
    @Published private(set) var recents: [URL] = []
    @Published private(set) var desktopIconsHidden = false

    /// Set by StatusItemController so actions can dismiss the popover first.
    var closePopover: (() -> Void)?

    private var thumbCache: [URL: NSImage] = [:]

    private init() {
        recents = Recents.list()
        desktopIconsHidden = Self.readDesktopIconsHidden()

        capture.onRecordingStateChange = { [weak self] in
            guard let self else { return }
            self.isRecording = self.capture.isRecording
        }
        capture.onCapture = { [weak self] url in
            guard let self else { return }
            self.recents = Recents.list()
            if Prefs.showThumbnail {
                ThumbnailPanel.show(for: url, services: self)
            }
        }
    }

    // MARK: - Capture actions (popover closes first so it isn't in the shot)

    private func afterPopoverCloses(_ block: @escaping () -> Void) {
        closePopover?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: block)
    }

    func captureArea() { afterPopoverCloses { self.capture.captureStill(.area) } }
    func captureWindow() { afterPopoverCloses { self.capture.captureStill(.window) } }
    func captureScreen() { afterPopoverCloses { self.capture.captureStill(.screen) } }
    func recordArea() { afterPopoverCloses { self.capture.startRecording(.area) } }
    func recordScreen() { afterPopoverCloses { self.capture.startRecording(.screen) } }
    func stopRecording() {
        closePopover?()
        capture.stopRecording()
    }

    // MARK: - Tools

    func copyTextFromScreen() {
        guard requirePro() else { return }
        afterPopoverCloses { OCRManager.captureAndCopyText() }
    }

    func pin(_ url: URL) {
        guard requirePro() else { return }
        closePopover?()
        PinWindow.show(url)
    }

    func pinLastCapture() {
        guard let url = recents.first(where: { $0.pathExtension.lowercased() != "mov" }) else {
            Toast.show("No screenshot to pin yet", symbol: "pin.slash", tint: .orange)
            return
        }
        pin(url)
    }

    func annotate(_ url: URL) {
        closePopover?()
        EditorWindowController.open(url)
    }

    func annotateLastCapture() {
        guard let url = recents.first(where: { $0.pathExtension.lowercased() != "mov" }) else {
            Toast.show("No screenshot to annotate yet", symbol: "pencil.slash", tint: .orange)
            return
        }
        annotate(url)
    }

    func copyImage(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let image = NSImage(contentsOf: url) {
            pb.writeObjects([image])
        } else {
            pb.writeObjects([url as NSURL])
        }
        Toast.show("Copied to clipboard")
    }

    func open(_ url: URL) {
        closePopover?()
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        closePopover?()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSaveFolder() {
        closePopover?()
        NSWorkspace.shared.open(Prefs.saveDirURL)
    }

    func clearRecents() {
        Recents.clear()
        recents = []
        thumbCache.removeAll()
    }

    // MARK: - Desktop icons (popular for clean recordings)

    func toggleDesktopIcons() {
        let hide = !desktopIconsHidden
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"]
        write.terminationHandler = { _ in
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = ["Finder"]
            try? kill.run()
        }
        try? write.run()
        desktopIconsHidden = hide
        Toast.show(hide ? "Desktop icons hidden" : "Desktop icons shown", symbol: hide ? "eye.slash" : "eye")
    }

    private static func readDesktopIconsHidden() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return out == "0" || out == "false"
    }

    // MARK: - Pro gating

    @discardableResult
    func requirePro() -> Bool {
        if LicenseManager.shared.isPro { return true }
        closePopover?()
        UpgradeWindowController.shared.show()
        return false
    }

    // MARK: - Thumbnails for the recents strip

    func thumbnail(for url: URL) -> NSImage? {
        if let cached = thumbCache[url] { return cached }
        guard url.pathExtension.lowercased() != "mov",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 200,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        thumbCache[url] = image
        return image
    }
}
