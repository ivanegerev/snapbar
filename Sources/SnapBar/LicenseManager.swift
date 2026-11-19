import Foundation
import Combine
import CryptoKit

/// SnapBar Pro licensing: 7-day full trial from first launch, then a license key
/// (one-time or subscription — both issue the same key format) unlocks Pro.
///
/// Keys are `SNAP2-<base64url(id)>.<base64url(signature)>`: an Ed25519 signature
/// over `keyDomain + id`, checked offline against the public key below, so the
/// app stays self-contained and keys can't be minted from this source. The
/// private key lives in store/.secrets-signing-key (gitignored) and the login
/// keychain; store/worker.js and `scripts/make-license.swift` sign with it.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    private static let keyStore = "licenseKey"
    private static let firstLaunchStore = "firstLaunchDate"
    static let trialLength = 7

    @Published private(set) var licenseKey: String?

    private init() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchStore) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstLaunchStore)
        }
        let stored = UserDefaults.standard.string(forKey: Self.keyStore)
        licenseKey = stored.flatMap { Self.isValidKey($0) || Self.isLegacyKey($0) ? $0 : nil }
    }

    var hasLicense: Bool { licenseKey != nil }

    var trialDaysLeft: Int {
        let start = UserDefaults.standard.object(forKey: Self.firstLaunchStore) as? Date ?? Date()
        let used = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        // A clock set back past the first launch makes `used` negative.
        return min(Self.trialLength, max(0, Self.trialLength - used))
    }

    var trialActive: Bool { trialDaysLeft > 0 }

    /// Pro features are available while licensed or trialing.
    var isPro: Bool { hasLicense || trialActive }

    var statusLabel: String {
        if hasLicense { return "Pro" }
        if trialActive { return "Trial · \(trialDaysLeft)d left" }
        return "Free"
    }

    @discardableResult
    func activate(_ raw: String) -> Bool {
        let key = Self.normalize(raw)
        guard Self.isValidKey(key) else { return false }
        UserDefaults.standard.set(key, forKey: Self.keyStore)
        licenseKey = key
        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: Self.keyStore)
        licenseKey = nil
    }

    // MARK: - Key validation

    private static let publicKey = Data(base64Encoded: "+vqZ+3+Kr7Unewu6zeKXFv4AZEya2zvyCuvixKOigdU=")!
    private static let keyDomain = "snapbar-license-v2:"
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Pulls the `SNAP2-…` key out of pasted text: drops whitespace (mail clients
    /// wrap long keys) and any label around it. Never changes case: base64url is
    /// case-sensitive. A signature is always 64 bytes = 86 base64url characters.
    static func normalize(_ raw: String) -> String {
        let compact = raw.filter { !$0.isWhitespace }
        guard let r = compact.range(of: "SNAP2-[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]{86}", options: .regularExpression)
        else { return compact }
        return String(compact[r])
    }

    static func isValidKey(_ key: String) -> Bool {
        guard key.hasPrefix("SNAP2-") else { return false }
        let parts = key.dropFirst(6).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = base64url(parts[0]), let sig = base64url(parts[1]),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { return false }
        return pub.isValidSignature(sig, for: Data(keyDomain.utf8) + id)
    }

    private static func base64url(_ s: Substring) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64)
    }

    // shortcut: legacy `SNAP-XXXXX-XXXXX-XXXXX` checksum keys are forgeable, so they're
    // honoured only when already stored on this Mac (honour system; anyone can write the
    // default). activate() never accepts them. Drop once no legacy keys are in use.
    static func isLegacyKey(_ raw: String) -> Bool {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.hasPrefix("SNAP"), cleaned.count == 19 else { return false }
        let values = cleaned.dropFirst(4).compactMap { ch in alphabet.firstIndex(of: ch) }
        guard values.count == 15 else { return false }
        return values.reduce(0, +) % 36 == 0
    }
}
