// Issues SnapBar Pro license keys by hand: SNAP2-<base64url(id)>.<base64url(sig)>,
// an Ed25519 signature over "snapbar-license-v2:" + a random 12-byte id — the
// format LicenseManager.isValidKey and store/worker.js use. The private key comes
// from store/.secrets-signing-key, else the login keychain item
// "snapbar-license-signing-key". Usage: swift scripts/make-license.swift [count]
import CryptoKit
import Foundation

func privateKeyBase64() -> String? {
    let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("store/.secrets-signing-key")
    if let s = try? String(contentsOf: file, encoding: .utf8) { return s }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "snapbar-license-signing-key", "-a", "snapbar", "-w"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

func base64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

guard let b64 = privateKeyBase64()?.trimmingCharacters(in: .whitespacesAndNewlines),
      let raw = Data(base64Encoded: b64),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else {
    FileHandle.standardError.write(Data("No signing key in store/.secrets-signing-key or the keychain.\n".utf8))
    exit(1)
}

let count = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 1 : 1
for _ in 0..<count {
    let id = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
    let sig = try key.signature(for: Data("snapbar-license-v2:".utf8) + id)
    print("SNAP2-\(base64url(id)).\(base64url(sig))")
}
