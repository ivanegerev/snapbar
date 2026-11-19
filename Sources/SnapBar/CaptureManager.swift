import AppKit

/// Drives /usr/sbin/screencapture for stills and recordings and reports results.
final class CaptureManager {
    private static let toolPath = "/usr/sbin/screencapture"

    enum StillKind { case area, window, screen }
    enum RecordingKind { case area, screen }

    private(set) var isRecording = false
    private(set) var recordingStartDate: Date?
    private var recordingProcess: Process?
    private var recordingURL: URL?
    private var stopSent = false
    private var stillInFlight = false

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

    private static var saveFolderName: String {
        (Prefs.saveDirURL.path as NSString).abbreviatingWithTildeInPath
    }

    /// A denied Desktop/Documents prompt or an unplugged drive only shows up
    /// on an actual write, and screencapture then fails silently — probe first.
    private static func ensureSaveDirWritable() -> Bool {
        let probe = Prefs.saveDirURL.appendingPathComponent(".snapbar-write-probe-\(UUID().uuidString)")
        if (try? Data().write(to: probe)) != nil {
            try? FileManager.default.removeItem(at: probe)
            return true
        }
        Toast.show("Can't save to \(saveFolderName) — choose another folder in Settings", symbol: "exclamationmark.triangle", tint: Brand.vermillion)
        return false
    }

    /// Our own thumbnail and toasts must not end up in the shot.
    private static func clearOverlays() {
        ThumbnailPanel.closeCurrent()
        Toast.hide()
    }

    /// Tags, records and announces a file screencapture just wrote.
    private static func didSave(_ url: URL) {
        CaptureTag.mark(url)
        Recents.add(url)
        NotificationCenter.default.post(name: AppServices.capturesChanged, object: url)
    }

    // MARK: - Stills

    func captureStill(_ kind: StillKind, delaySeconds: Int? = nil) {
        // A second press while screencapture is still running would share its file name.
        guard !stillInFlight, Self.ensureScreenPermission(), Self.ensureSaveDirWritable() else { return }
        Self.clearOverlays()
        var args: [String] = []
        switch kind {
        case .area:
            args.append("-i")
        case .window:
            args += ["-i", "-W"]
        case .screen:
            if Prefs.showCursor { args.append("-C") }
        }
        // Space toggles an area capture into window mode, so -o applies there too.
        if kind != .screen && !Prefs.windowShadow { args.append("-o") }
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
                self?.stillInFlight = false
                let saved = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                guard let first = saved.first else {
                    // Interactive captures can be cancelled with Escape — that's
                    // normal. A missing file on a non-interactive capture isn't.
                    if kind == .screen {
                        if ScreenPermission.granted {
                            Toast.show("Capture didn't save to \(Self.saveFolderName)", symbol: "exclamationmark.triangle", tint: Brand.vermillion)
                        } else {
                            Toast.show("Capture didn't complete — check Screen Recording permission", symbol: "exclamationmark.triangle", tint: .orange)
                            PermissionWindowController.shared.show()
                        }
                    }
                    return
                }
                // Secondary displays go straight to recents; the primary shot
                // drives the thumbnail/editor flow.
                for extra in saved.dropFirst() { Self.didSave(extra) }
                Self.didSave(first)
                self?.finishStill(url: first)
            }
        }
        stillInFlight = true
        do { try proc.run() } catch { stillInFlight = false }
    }

    private func finishStill(url: URL) {
        if Prefs.copyToClipboard, let image = NSImage(contentsOf: url) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }
        onCapture?(url)
    }

    // MARK: - Recording

    func startRecording(_ kind: RecordingKind) {
        guard !isRecording else { return }
        guard Self.ensureScreenPermission(), Self.ensureSaveDirWritable() else { return }
        Self.clearOverlays()

        var args = ["-v"]
        if kind == .area { args.append("-Jvideo") }
        if Prefs.recordMicrophone { args.append("-g") }
        if Prefs.showClicks { args.append("-k") }
        if !Prefs.playSound { args.append("-x") }

        let url = Prefs.newFileURL(prefix: Prefs.recordingPrefix, ext: "mov")
        args.append(url.path)

        let proc = makeProcess(args: args)
        proc.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                // stopRecordingAndWait may already have finished this recording.
                guard let self, self.recordingProcess === finished else { return }
                self.resetRecordingState()
                guard FileManager.default.fileExists(atPath: url.path) else {
                    // Cancelling the interactive recording toolbar (Esc) is
                    // normal; only complain when permission is the culprit.
                    if !ScreenPermission.granted {
                        Toast.show("Recording didn't save — Screen Recording permission is off", symbol: "exclamationmark.triangle", tint: .orange)
                        PermissionWindowController.shared.show()
                    }
                    return
                }
                Self.didSave(url)
                self.onCapture?(url)
            }
        }
        do {
            try proc.run()
        } catch {
            return
        }
        recordingProcess = proc
        recordingURL = url
        recordingStartDate = Date()
        isRecording = true
        onRecordingStateChange?()
    }

    /// SIGINT makes screencapture stop and finalize the movie file. Sent once:
    /// a second SIGINT can cut the finalize short.
    func stopRecording() {
        guard let proc = recordingProcess, proc.isRunning, !stopSent else { return }
        stopSent = true
        proc.interrupt()
    }

    /// Quit path: the main-queue terminationHandler never runs once the app is
    /// exiting, so wait for screencapture here and file the movie inline
    /// (no editor or thumbnail).
    func stopRecordingAndWait(timeout: TimeInterval = 5) {
        guard let proc = recordingProcess, let url = recordingURL else { return }
        stopRecording()
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { usleep(20_000) }
        resetRecordingState()
        if FileManager.default.fileExists(atPath: url.path) { Self.didSave(url) }
    }

    private func resetRecordingState() {
        isRecording = false
        recordingStartDate = nil
        recordingProcess = nil
        recordingURL = nil
        stopSent = false
        onRecordingStateChange?()
    }

    private func makeProcess(args: [String]) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.toolPath)
        proc.arguments = args
        return proc
    }
}
