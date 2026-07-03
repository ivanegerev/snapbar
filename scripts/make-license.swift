// Generates valid SnapBar Pro license keys (SNAP-XXXXX-XXXXX-XXXXX).
// The 15-char base-36 body must have a digit sum divisible by 36 — matching
// LicenseManager.isValidKey. Usage: swift make-license.swift [count]
import Foundation

let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
let count = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 1 : 1

for _ in 0..<count {
    var values = (0..<14).map { _ in Int.random(in: 0..<36) }
    let remainder = values.reduce(0, +) % 36
    values.append((36 - remainder) % 36)
    let body = values.map { String(alphabet[$0]) }.joined()
    let groups = stride(from: 0, to: 15, by: 5).map {
        String(body[body.index(body.startIndex, offsetBy: $0)..<body.index(body.startIndex, offsetBy: $0 + 5)])
    }
    print("SNAP-" + groups.joined(separator: "-"))
}
