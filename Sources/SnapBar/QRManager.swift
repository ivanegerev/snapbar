import AppKit
import Vision

/// "Scan QR Code": select an area, Vision decodes any barcode in it. The
/// payload lands on the clipboard; http(s) links open in the browser too.
enum QRManager {
    static func scanFromScreen() {
        guard ScreenPermission.granted else {
            PermissionWindowController.shared.show()
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapbar-qr-\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-x", "-t", "png", tmp.path]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async { detect(tmp) }
        }
        try? proc.run()
    }

    private static func detect(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        try? FileManager.default.removeItem(at: url)

        let request = VNDetectBarcodesRequest { req, _ in
            let payload = (req.results as? [VNBarcodeObservation])?
                .compactMap { $0.payloadStringValue }
                .first
            DispatchQueue.main.async {
                guard let payload else {
                    Toast.show("No QR or barcode found in selection", symbol: "qrcode", tint: .orange)
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(payload, forType: .string)
                if let link = URL(string: payload),
                   let scheme = link.scheme?.lowercased(),
                   ["http", "https"].contains(scheme) {
                    NSWorkspace.shared.open(link)
                    Toast.show("QR link opened — also on your clipboard", symbol: "qrcode")
                } else {
                    Toast.show("QR contents copied", symbol: "qrcode")
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }
}
