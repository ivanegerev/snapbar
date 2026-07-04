import Foundation

/// UserDefaults-backed preferences. Keys match the @AppStorage keys in SettingsView.
enum Prefs {
    static let defaults: [String: Any] = [
        "saveDir": NSHomeDirectory() + "/Desktop",
        "format": "png",
        "copyToClipboard": false,
        "showThumbnail": true,
        "openEditorAfterCapture": true,
        "playSound": true,
        "windowShadow": true,
        "showCursor": true,
        "delaySeconds": 0,
        "recordMicrophone": false,
        "showClicks": false,
        "recentCaptures": [String](),
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    static var saveDir: String { UserDefaults.standard.string(forKey: "saveDir") ?? NSHomeDirectory() + "/Desktop" }
    static var format: String { UserDefaults.standard.string(forKey: "format") ?? "png" }
    static var copyToClipboard: Bool { UserDefaults.standard.bool(forKey: "copyToClipboard") }
    static var showThumbnail: Bool { UserDefaults.standard.bool(forKey: "showThumbnail") }
    static var openEditorAfterCapture: Bool { UserDefaults.standard.bool(forKey: "openEditorAfterCapture") }
    static var playSound: Bool { UserDefaults.standard.bool(forKey: "playSound") }
    static var windowShadow: Bool { UserDefaults.standard.bool(forKey: "windowShadow") }
    static var showCursor: Bool { UserDefaults.standard.bool(forKey: "showCursor") }
    static var delaySeconds: Int { UserDefaults.standard.integer(forKey: "delaySeconds") }
    static var recordMicrophone: Bool { UserDefaults.standard.bool(forKey: "recordMicrophone") }
    static var showClicks: Bool { UserDefaults.standard.bool(forKey: "showClicks") }

    static var saveDirURL: URL {
        let url = URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a unique "Screenshot 2026-07-03 at 10.15.30.png"-style URL in the save folder.
    static func newFileURL(prefix: String, ext: String) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = fmt.string(from: Date())
        let dir = saveDirURL
        var url = dir.appendingPathComponent("\(prefix) \(stamp).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(prefix) \(stamp) (\(counter)).\(ext)")
            counter += 1
        }
        return url
    }
}

/// Rolling list of recent capture file paths, persisted in UserDefaults.
enum Recents {
    private static let key = "recentCaptures"
    private static let capacity = 12

    static func add(_ url: URL) {
        var paths = list().map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > capacity { paths = Array(paths.prefix(capacity)) }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func list() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func clear() {
        UserDefaults.standard.set([String](), forKey: key)
    }
}
