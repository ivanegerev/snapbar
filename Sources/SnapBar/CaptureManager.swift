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

    // MARK: - Stills

    func captureStill(_ kind: StillKind) {
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
        if Prefs.delaySeconds > 0 { args.append("-T\(Prefs.delaySeconds)") }
        args += ["-t", Prefs.format]

        let url = Prefs.newFileURL(prefix: "Screenshot", ext: Prefs.format)
        args.append(url.path)

        let proc = makeProcess(args: args)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                // Interactive captures can be cancelled with Escape — no file, nothing to do.
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                self?.finishStill(url: url)
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

        var args = ["-v"]
        if kind == .area { args.append("-Jvideo") }
        if Prefs.recordMicrophone { args.append("-g") }
        if Prefs.showClicks { args.append("-k") }
        if !Prefs.playSound { args.append("-x") }

        let url = Prefs.newFileURL(prefix: "Screen Recording", ext: "mov")
        args.append(url.path)

        let proc = makeProcess(args: args)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.recordingStartDate = nil
                self.recordingProcess = nil
                self.onRecordingStateChange?()
                guard FileManager.default.fileExists(atPath: url.path) else { return }
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
