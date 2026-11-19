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
    @Published private(set) var recents: [URL] = [] {
        // Keeps the cache to what the strip can show; it otherwise grew for the life of the process.
        didSet { thumbCache = thumbCache.filter { recents.contains($0.key) } }
    }
    @Published private(set) var desktopIconsHidden = false

    /// Set by StatusItemController so actions can dismiss the popover first.
    var closePopover: (() -> Void)?
    var popoverIsShown: () -> Bool = { false }

    private var thumbCache: [URL: NSImage] = [:]

    private init() {
        recents = Recents.list()
        desktopIconsHidden = Self.readDesktopIconsHidden()

        capture.onRecordingStateChange = { [weak self] in
            guard let self else { return }
            self.isRecording = self.capture.isRecording
        }
        // Editors, exports and housekeeping announce file changes here; the URL
        // (when given) may have been overwritten in place, so its thumbnail is stale.
        NotificationCenter.default.addObserver(forName: Self.capturesChanged, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if let url = note.object as? URL {
                self.thumbCache = self.thumbCache.filter { $0.key.path != url.path }
            } else {
                self.thumbCache.removeAll()
            }
            self.recents = Recents.list()
        }
        capture.onCapture = { [weak self] url in
            guard let self else { return }
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
        guard popoverIsShown() else { return block() }
        closePopover?()
        // Opening the popover activated SnapBar; hand focus back so the target
        // window is shot active and keystrokes return to it afterwards.
        if NSApp.isActive && NSApp.mainWindow == nil { NSApp.deactivate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: block)
    }

    func captureArea() { afterPopoverCloses { self.capture.captureStill(.area) } }
    func captureWindow() { afterPopoverCloses { self.capture.captureStill(.window) } }
    func captureScreen() { afterPopoverCloses { self.capture.captureStill(.screen) } }
    func captureScreen(after seconds: Int) {
        afterPopoverCloses { self.capture.captureStill(.screen, delaySeconds: seconds) }
    }
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

    func scanQRCode() {
        guard requirePro() else { return }
        afterPopoverCloses { QRManager.scanFromScreen() }
    }

    /// Paste an image from the clipboard into the markup editor.
    func annotateClipboardImage() {
        closePopover?()
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            Toast.show("No image on the clipboard", symbol: "clipboard", tint: .orange)
            return
        }
        let url = Prefs.newFileURL(prefix: "Pasted", ext: "png")
        do {
            try png.write(to: url)
        } catch {
            Toast.show("Couldn't save the pasted image", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        CaptureTag.mark(url)
        Recents.add(url)
        NotificationCenter.default.post(name: Self.capturesChanged, object: url)
        EditorWindowController.open(url)
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
        NSWorkspace.shared.recycle([url]) { _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    Toast.show("Couldn't move to Trash", symbol: "exclamationmark.triangle", tint: .orange)
                    return
                }
                Recents.remove(url)
                Toast.show("Moved to Trash", symbol: "trash")
                NotificationCenter.default.post(name: Self.capturesChanged, object: url)
            }
        }
    }

    // MARK: - Housekeeping

    /// Trash captures older than the configured age. Only files SnapBar tagged
    /// when it created them qualify; matching on the name prefix alone also
    /// swept up the user's own ⇧⌘4 screenshots, which macOS names identically.
    func runAutoCleanup() {
        let days = Prefs.autoCleanupDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let dir = Prefs.saveDirURL

        DispatchQueue.global(qos: .utility).async {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )) ?? []
            let old = urls.filter { url in
                guard CaptureTag.isMarked(url) else { return false }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date()
                return date < cutoff
            }
            guard !old.isEmpty else { return }
            // Untag before trashing: Finder's Put Back keeps the xattr and the old
            // mtime, so a restored capture would otherwise be trashed again next run.
            old.forEach(CaptureTag.unmark)
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(old) { moved, _ in
                    DispatchQueue.main.async {
                        let failed = old.filter { moved[$0] == nil }
                        failed.forEach(CaptureTag.mark)
                        if moved.isEmpty {
                            Toast.show("Couldn't tidy old captures into the Trash", symbol: "exclamationmark.triangle", tint: .orange)
                            return
                        }
                        var message = "Tidied \(moved.count) old capture\(moved.count == 1 ? "" : "s") into the Trash"
                        if !failed.isEmpty { message += " · \(failed.count) couldn't be moved" }
                        Toast.show(message, symbol: "trash", tint: failed.isEmpty ? .green : .orange)
                        NotificationCenter.default.post(name: Self.capturesChanged, object: nil)
                    }
                }
            }
        }
    }

    /// Once a day, see if a newer release is out (GitHub is the update channel).
    func checkForUpdatesIfDue() {
        guard Prefs.autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 * 0.9 else { return }

        let url = URL(string: "https://api.github.com/repos/ivanegerev/snapbar/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            // Only a real answer uses up the day; a launch with no network retries on the next tick.
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
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
