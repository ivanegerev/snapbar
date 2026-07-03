import Foundation
import Combine

/// SnapBar Pro licensing: 7-day full trial from first launch, then a license key
/// (one-time or subscription — both issue the same key format) unlocks Pro.
///
/// Keys are `SNAP-XXXXX-XXXXX-XXXXX` (base-36 body whose digit sum is divisible
/// by 36). Offline checksum validation keeps the app self-contained; a production
/// storefront (Paddle / Lemon Squeezy / Stripe) would additionally verify the key
/// against its API here. `scripts/make-license.swift` generates valid keys.
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
        licenseKey = stored.flatMap { Self.isValidKey($0) ? $0 : nil }
    }

    var hasLicense: Bool { licenseKey != nil }

    var trialDaysLeft: Int {
        let start = UserDefaults.standard.object(forKey: Self.firstLaunchStore) as? Date ?? Date()
        let used = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialLength - used)
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
        guard Self.isValidKey(raw) else { return false }
        let key = Self.normalize(raw)
        UserDefaults.standard.set(key, forKey: Self.keyStore)
        licenseKey = key
        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: Self.keyStore)
        licenseKey = nil
    }

    // MARK: - Key validation

    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func normalize(_ raw: String) -> String {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 19 else { return raw.uppercased() }
        let body = Array(cleaned.dropFirst(4))
        let groups = stride(from: 0, to: 15, by: 5).map { String(body[$0..<$0 + 5]) }
        return "SNAP-" + groups.joined(separator: "-")
    }

    static func isValidKey(_ raw: String) -> Bool {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.hasPrefix("SNAP"), cleaned.count == 19 else { return false }
        let values = cleaned.dropFirst(4).compactMap { ch in alphabet.firstIndex(of: ch) }
        guard values.count == 15 else { return false }
        return values.reduce(0, +) % 36 == 0
    }
}
