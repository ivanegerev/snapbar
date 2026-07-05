import AppKit
import Combine
import ImageIO

/// Central hub the UI talks to: owns the capture engine, publishes state for
/// SwiftUI, and hosts the actions shared by the popover, hotkeys and thumbnails.
final class AppServices: ObservableObject {
    static let shared = AppServices()

    /// Posted whenever files in the capture folder change (new capture, trash, cleanup).
    static let capturesChanged = Notification.Name("SnapBarCapturesChanged")

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
            NotificationCenter.default.post(name: Self.capturesChanged, object: nil)
            if Prefs.openEditorAfterCapture {
                // Straight into editing — the editor covers copy/save, so the
                // floating thumbnail would just be noise on top of it.
                if url.pathExtension.lowercased() == "mov" {
                    ClipEditorWindowController.open(url)
                } else {
                    EditorWindowController.open(url)
                }
            } else if Prefs.showThumbnail {
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

    func editClip(_ url: URL) {
        closePopover?()
        ClipEditorWindowController.open(url)
    }

    // MARK: - Color picker

    private var colorSampler: NSColorSampler?

    /// System eyedropper — pick any pixel on screen, hex lands on the clipboard.
    func pickColor() {
        closePopover?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            let sampler = NSColorSampler()
            self?.colorSampler = sampler
            sampler.show { color in
                DispatchQueue.main.async {
                    self?.colorSampler = nil
                    guard let color, let rgb = color.usingColorSpace(.sRGB) else { return }
                    let hex = String(
                        format: "#%02X%02X%02X",
                        Int((rgb.redComponent * 255).rounded()),
                        Int((rgb.greenComponent * 255).rounded()),
                        Int((rgb.blueComponent * 255).rounded())
                    )
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(hex, forType: .string)
                    Toast.show("\(hex) copied", symbol: "eyedropper")
                }
            }
        }
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

    func openHistory() {
        closePopover?()
        HistoryWindowController.shared.show()
    }

    func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
        Toast.show("Path copied")
    }

    func trash(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    Toast.show("Couldn't move to Trash", symbol: "exclamationmark.triangle", tint: .orange)
                    return
                }
                Recents.remove(url)
                self?.recents = Recents.list()
                self?.thumbCache[url] = nil
                Toast.show("Moved to Trash", symbol: "trash")
                NotificationCenter.default.post(name: Self.capturesChanged, object: nil)
            }
        }
    }

    // MARK: - Housekeeping

    /// Trash captures older than the configured age (only files matching the
    /// app's own naming prefixes — never other files in the folder).
    func runAutoCleanup() {
        let days = Prefs.autoCleanupDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let prefixes = [Prefs.screenshotPrefix, Prefs.recordingPrefix]
        let dir = Prefs.saveDirURL

        DispatchQueue.global(qos: .utility).async {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )) ?? []
            let old = urls.filter { url in
                guard prefixes.contains(where: { url.lastPathComponent.hasPrefix($0 + " ") }) else { return false }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date()
                return date < cutoff
            }
            guard !old.isEmpty else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(old) { _, error in
                    guard error == nil else { return }
                    Toast.show("Tidied \(old.count) old capture\(old.count == 1 ? "" : "s") into the Trash", symbol: "trash")
                    NotificationCenter.default.post(name: Self.capturesChanged, object: nil)
                }
            }
        }
    }

    /// Once a day, see if a newer release is out (GitHub is the update channel).
    func checkForUpdatesIfDue() {
        guard Prefs.autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 * 0.9 else { return }
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")

        let url = URL(string: "https://api.github.com/repos/ivanegerev/snapbar/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard Self.version(remote, isNewerThan: local) else { return }
            DispatchQueue.main.async {
                Toast.show("SnapBar \(tag) is out — right-click the menu icon → Check for Updates", symbol: "arrow.down.circle", tint: .blue)
            }
        }.resume()
    }

    private static func version(_ a: String, isNewerThan b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
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
