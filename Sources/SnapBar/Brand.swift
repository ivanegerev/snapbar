import SwiftUI
import AppKit

/// "Contact Sheet" palette — see BRAND.md. Flat print colors, no gradients.
enum Brand {
    /// #E14E1D — the grease pencil. Accent, used sparingly.
    static let vermillion = Color(red: 0.882, green: 0.306, blue: 0.114)
    /// #1A1713 — text, borders, "negative" surfaces.
    static let ink = Color(red: 0.102, green: 0.090, blue: 0.075)
    /// #F2EEE3 — warm bone paper.
    static let paper = Color(red: 0.949, green: 0.933, blue: 0.890)
    /// #FFFDF7 — raised cream surfaces on paper.
    static let cream = Color(red: 1.0, green: 0.992, blue: 0.969)
    /// #6B6558 — secondary text on paper.
    static let graphite = Color(red: 0.420, green: 0.396, blue: 0.345)
    /// Hairline rules on paper.
    static let hairline = Color(red: 0.102, green: 0.090, blue: 0.075).opacity(0.22)

    static let nsVermillion = NSColor(red: 0.882, green: 0.306, blue: 0.114, alpha: 1)
    static let nsInk = NSColor(red: 0.102, green: 0.090, blue: 0.075, alpha: 1)
    static let nsPaper = NSColor(red: 0.949, green: 0.933, blue: 0.890, alpha: 1)
}
