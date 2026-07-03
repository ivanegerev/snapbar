import SwiftUI
import AppKit

/// The "SnapBar Pro" purchase / license activation window.
/// Buy buttons open the website checkout (placeholder URLs — wire to your
/// Paddle / Lemon Squeezy / Stripe checkout when the storefront is live).
struct UpgradeView: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var keyInput = ""
    @State private var activationFailed = false


    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 18) {
                featureGrid
                if license.hasLicense {
                    activatedBox
                } else {
                    pricingCards
                    Divider()
                    activationRow
                }
            }
            .padding(22)
        }
        .frame(width: 480)
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Brand.paper)
                Circle()
                    .fill(Brand.vermillion)
                    .frame(width: 9, height: 9)
            }
            Text("SnapBar Pro")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Brand.paper)
            Text(license.hasLicense
                 ? "Pro is active on this Mac — thank you!"
                 : license.trialActive
                    ? "EVERYTHING UNLOCKED · \(license.trialDaysLeft) TRIAL DAYS LEFT"
                    : "YOUR TRIAL HAS ENDED — KEEP THE GOOD STUFF")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.paper.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Brand.ink)
    }

    private var featureGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                feature("text.viewfinder", "OCR — copy text from screen")
                feature("pin", "Pin screenshots on top")
            }
            GridRow {
                feature("sparkles", "Beautify backgrounds & padding")
                feature("checkerboard.rectangle", "Pixelate sensitive info")
            }
            GridRow {
                feature("arrow.triangle.2.circlepath", "Free updates")
                feature("heart", "Support an indie app")
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Brand.vermillion)
                .frame(width: 16)
            Text(text).font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pricingCards: some View {
        HStack(spacing: 14) {
            pricingCard(
                title: "Lifetime",
                price: "$14.99",
                caption: "One-time payment.\nYours forever.",
                highlighted: true,
                url: "https://ivanegerev.github.io/snapbar/buy.html?plan=lifetime"
            )
            pricingCard(
                title: "Monthly",
                price: "$1.99/mo",
                caption: "Cancel anytime.\nSame features.",
                highlighted: false,
                url: "https://ivanegerev.github.io/snapbar/buy.html?plan=monthly"
            )
        }
    }

    private func pricingCard(title: String, price: String, caption: String, highlighted: Bool, url: String) -> some View {
        VStack(spacing: 8) {
            if highlighted {
                Text("THE KEEPER")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.vermillion))
                    .foregroundStyle(.white)
            } else {
                Spacer().frame(height: 18)
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(price).font(.system(size: 22, weight: .bold))
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link(destination: URL(string: url)!) {
                Text(highlighted ? "Buy Once" : "Subscribe")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(highlighted ? Brand.vermillion : .secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlighted ? Brand.vermillion.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: highlighted ? 1.5 : 1)
        )
    }

    private var activationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Already purchased? Enter your license key:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                TextField("SNAP-XXXXX-XXXXX-XXXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("Activate") {
                    activationFailed = !LicenseManager.shared.activate(keyInput)
                    if !activationFailed { Toast.show("SnapBar Pro activated — welcome aboard", symbol: "checkmark.seal.fill") }
                }
                .disabled(keyInput.isEmpty)
            }
            if activationFailed {
                Text("That key doesn't look right — check for typos.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var activatedBox: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(license.licenseKey ?? "")
                    .font(.system(size: 12, design: .monospaced))
            }
            Button("Deactivate on this Mac") { license.deactivate() }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
    }
}

final class UpgradeWindowController {
    static let shared = UpgradeWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: UpgradeView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "SnapBar Pro"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
