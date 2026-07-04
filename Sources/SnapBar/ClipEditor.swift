import SwiftUI
import AVKit
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Editor window for screen recordings: QuickTime-style trimming via
/// AVPlayerView, passthrough export (no re-encode), and GIF export (Pro).
final class ClipEditorModel: ObservableObject {
    let url: URL
    let player: AVPlayer
    weak var playerView: AVPlayerView?

    @Published var isTrimming = false
    @Published var hasTrim = false
    @Published var isExporting = false
    @Published var info = ""

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
        loadInfo()
    }

    private func loadInfo() {
        let asset = AVAsset(url: url)
        Task { @MainActor in
            let duration = (try? await asset.load(.duration)) ?? .zero
            let seconds = Int(CMTimeGetSeconds(duration).rounded())
            var parts = [String(format: "%d:%02d", seconds / 60, seconds % 60)]
            if let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            info = parts.joined(separator: " · ")
        }
    }

    // MARK: - Trim

    func beginTrim() {
        guard let pv = playerView else { return }
        guard pv.canBeginTrimming else {
            Toast.show("This clip can't be trimmed", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        player.pause()
        isTrimming = true
        pv.beginTrimming { [weak self] result in
            DispatchQueue.main.async {
                self?.isTrimming = false
                if result == .okButton { self?.hasTrim = true }
            }
        }
    }

    /// The selected range after trimming, or nil for the whole clip.
    private var exportRange: CMTimeRange? {
        guard let item = player.currentItem else { return nil }
        let duration = item.asset.duration
        var start = CMTime.zero
        var end = duration
        if item.reversePlaybackEndTime.isValid, item.reversePlaybackEndTime > .zero {
            start = item.reversePlaybackEndTime
        }
        if item.forwardPlaybackEndTime.isValid, item.forwardPlaybackEndTime < duration {
            end = item.forwardPlaybackEndTime
        }
        guard start > .zero || end < duration else { return nil }
        guard end > start else { return nil }
        return CMTimeRange(start: start, end: end)
    }

    /// Default destination: "<original name> trimmed.mov", uniquified.
    func defaultSaveURL() -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(base) trimmed.mov")
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) trimmed (\(counter)).mov")
            counter += 1
        }
        return dest
    }

    func saveTrimmed(to dest: URL) {
        guard let item = player.currentItem,
              let export = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetPassthrough)
        else {
            Toast.show("Export failed", symbol: "exclamationmark.triangle", tint: .orange)
            return
        }
        try? FileManager.default.removeItem(at: dest)
        export.outputFileType = .mov
        export.outputURL = dest
        if let range = exportRange { export.timeRange = range }

        isExporting = true
        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                self?.isExporting = false
                if export.status == .completed {
                    Recents.add(dest)
                    Toast.show("Saved \(dest.lastPathComponent)")
                } else {
                    Toast.show("Export failed", symbol: "exclamationmark.triangle", tint: .orange)
                }
            }
        }
    }

    // MARK: - GIF export

    func exportGIF(to dest: URL) {
        isExporting = true
        let asset = AVAsset(url: url)
        let range = exportRange

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fullDuration = CMTimeGetSeconds(asset.duration)
            let startSec = range.map { CMTimeGetSeconds($0.start) } ?? 0
            let duration = range.map { CMTimeGetSeconds($0.duration) } ?? fullDuration

            let fps = 10.0
            var step = 1.0 / fps
            var frameCount = max(Int(duration * fps), 1)
            if frameCount > 240 { // cap file size on long clips
                frameCount = 240
                step = duration / 240
            }

            try? FileManager.default.removeItem(at: dest)
            guard let destination = CGImageDestinationCreateWithURL(
                dest as CFURL, UTType.gif.identifier as CFString, frameCount, nil
            ) else {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    Toast.show("GIF export failed", symbol: "exclamationmark.triangle", tint: .orange)
                }
                return
            }
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
            ] as CFDictionary)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.03, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)

            let frameProps = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: step]
            ] as CFDictionary

            for i in 0..<frameCount {
                let t = CMTime(seconds: startSec + Double(i) * step, preferredTimescale: 600)
                if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
                    CGImageDestinationAddImage(destination, cg, frameProps)
                }
            }
            let ok = CGImageDestinationFinalize(destination)

            DispatchQueue.main.async {
                self?.isExporting = false
                if ok {
                    Recents.add(dest)
                    Toast.show("Saved \(dest.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                } else {
                    Toast.show("GIF export failed", symbol: "exclamationmark.triangle", tint: .orange)
                }
            }
        }
    }
}

// MARK: - Player view

private struct ClipPlayerRepresentable: NSViewRepresentable {
    let model: ClipEditorModel

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        model.playerView = view
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// MARK: - View

struct ClipEditorView: View {
    @ObservedObject var model: ClipEditorModel
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ClipPlayerRepresentable(model: model)
                .frame(minWidth: 560, minHeight: 340)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                model.beginTrim()
            } label: {
                Label("Trim", systemImage: "timeline.selection")
            }
            .disabled(model.isTrimming || model.isExporting)
            .help("Trim the clip (like QuickTime)")

            Button {
                exportGIF()
            } label: {
                Label(license.isPro ? "Export GIF" : "Export GIF (Pro)", systemImage: "photo.stack")
            }
            .disabled(model.isExporting)

            if model.hasTrim {
                Text("TRIMMED")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.vermillion))
                    .foregroundStyle(.white)
            }

            Text(model.info)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if model.isExporting {
                ProgressView().controlSize(.small)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([model.url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button("Save As…") { saveAs() }
                .disabled(model.isExporting)

            Button("Save") { model.saveTrimmed(to: model.defaultSaveURL()) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting)
                .help("Saves a trimmed copy next to the original")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func exportGIF() {
        guard license.isPro else {
            UpgradeWindowController.shared.show()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.url.deletingPathExtension().lastPathComponent + ".gif"
        panel.directoryURL = Prefs.saveDirURL
        if panel.runModal() == .OK, let dest = panel.url {
            model.exportGIF(to: dest)
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.url.deletingPathExtension().lastPathComponent + " trimmed.mov"
        panel.directoryURL = model.url.deletingLastPathComponent()
        if panel.runModal() == .OK, let dest = panel.url {
            model.saveTrimmed(to: dest)
        }
    }
}

// MARK: - Window controller

enum ClipEditorWindowController {
    private static var windows: [NSWindow] = []

    static func open(_ url: URL) {
        let model = ClipEditorModel(url: url)
        let hosting = NSHostingController(rootView: ClipEditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clip — \(url.lastPathComponent)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        windows.append(window)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { note in
            if let win = note.object as? NSWindow {
                windows.removeAll { $0 === win }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
