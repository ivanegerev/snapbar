import AppKit

/// Drives /usr/sbin/screencapture for stills and recordings and reports results.
final class CaptureManager {
    private static let toolPath = "/usr/sbin/screencapture"

    enum StillKind { case area, window, screen }
    enum RecordingKind { case area, screen }

    private(set) var isRecording = false
    private(set) var recordingStartDate: Date?
    private var recordingProcess: Process?

    /// Called on the main thread whenever recording starts or stops.
    var onRecordingStateChange: (() -> Void)?
    /// Called on the main thread with the finished file (screenshot or recording).
    var onCapture: ((URL) -> Void)?

    /// Without Screen Recording permission, screencapture fails silently (or
    /// produces black frames). Gate every capture and show the setup window
    /// instead of doing nothing.
    private static func ensureScreenPermission() -> Bool {
        if ScreenPermission.granted { return true }
        DispatchQueue.main.async { PermissionWindowController.shared.show() }
        return false
    }

    // MARK: - Stills

    func captureStill(_ kind: StillKind, delaySeconds: Int? = nil) {
        guard Self.ensureScreenPermission() else { return }
        var args: [String] = []
        switch kind {
        case .area:
            args.append("-i")
        case .window:
            args += ["-i", "-W"]
            if !Prefs.windowShadow { args.append("-o") }
        case .screen:
            if Prefs.showCursor { args.append("-C") }
        }
        if !Prefs.playSound { args.append("-x") }
        let delay = delaySeconds ?? Prefs.delaySeconds
        if delay > 0 { args.append("-T\(delay)") }
        args += ["-t", Prefs.format]

        // Full-screen capture writes one file per display.
        var urls = [Prefs.newFileURL(prefix: Prefs.screenshotPrefix, ext: Prefs.format)]
        if kind == .screen {
            let screens = max(NSScreen.screens.count, 1)
            for i in 2...max(screens, 2) where i <= screens {
                urls.append(Prefs.newFileURL(prefix: "\(Prefs.screenshotPrefix) (Display \(i))", ext: Prefs.format))
            }
        }
        args += urls.map(\.path)

        let proc = makeProcess(args: args)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                let saved = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                guard let first = saved.first else {
                    // Interactive captures can be cancelled with Escape — that's
                    // normal. A missing file on a non-interactive capture isn't.
                    if kind == .screen {
                        Toast.show("Capture didn't complete — check Screen Recording permission", symbol: "exclamationmark.triangle", tint: .orange)
                        PermissionWindowController.shared.show()
                    }
                    return
                }
                // Secondary displays go straight to recents; the primary shot
                // drives the thumbnail/editor flow.
                for extra in saved.dropFirst() { Recents.add(extra) }
                self?.finishStill(url: first)
            }
        }
        try? proc.run()
    }

    private func finishStill(url: URL) {
        if Prefs.copyToClipboard, let image = NSImage(contentsOf: url) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }
        Recents.add(url)
        onCapture?(url)
    }

    // MARK: - Recording

    func startRecording(_ kind: RecordingKind) {
        guard !isRecording else { return }
        guard Self.ensureScreenPermission() else { return }

        var args = ["-v"]
        if kind == .area { args.append("-Jvideo") }
        if Prefs.recordMicrophone { args.append("-g") }
        if Prefs.showClicks { args.append("-k") }
        if !Prefs.playSound { args.append("-x") }

        let url = Prefs.newFileURL(prefix: Prefs.recordingPrefix, ext: "mov")
        args.append(url.path)

        let proc = makeProcess(args: args)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.recordingStartDate = nil
                self.recordingProcess = nil
                self.onRecordingStateChange?()
                guard FileManager.default.fileExists(atPath: url.path) else {
                    // Cancelling the interactive recording toolbar (Esc) is
                    // normal; only complain when permission is the culprit.
                    if !ScreenPermission.granted {
                        Toast.show("Recording didn't save — Screen Recording permission is off", symbol: "exclamationmark.triangle", tint: .orange)
                        PermissionWindowController.shared.show()
                    }
                    return
                }
                Recents.add(url)
                self.onCapture?(url)
            }
        }
        do {
            try proc.run()
        } catch {
            return
        }
        recordingProcess = proc
        recordingStartDate = Date()
        isRecording = true
        onRecordingStateChange?()
    }

    /// SIGINT makes screencapture stop and finalize the movie file.
    func stopRecording() {
        recordingProcess?.interrupt()
    }

    private func makeProcess(args: [String]) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.toolPath)
        proc.arguments = args
        return proc
    }
}
