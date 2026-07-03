import AppKit
import Vision

/// "Copy Text from Screen": select an area, OCR it with Vision, put the text on
/// the clipboard. The capture goes to a temp file and is deleted immediately.
enum OCRManager {
    static func captureAndCopyText() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapbar-ocr-\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-x", "-t", "png", tmp.path]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async { recognize(tmp) }
        }
        try? proc.run()
    }

    private static func recognize(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        try? FileManager.default.removeItem(at: url)

        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            DispatchQueue.main.async {
                guard !lines.isEmpty else {
                    Toast.show("No text found in selection", symbol: "eye.slash", tint: .orange)
                    return
                }
                let text = lines.joined(separator: "\n")
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                Toast.show("Copied \(text.count) characters", symbol: "text.viewfinder")
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }
}
