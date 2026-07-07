import SwiftUI
import AppKit

/// The menu bar dropdown, styled as the brand's "contact sheet": warm paper,
/// ink hairlines, a serif wordmark, mono spec labels and one vermillion accent.
struct MenuPopoverView: View {
    @EnvironmentObject var services: AppServices
    @ObservedObject private var license = LicenseManager.shared

    static let badge = Brand.vermillion

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            section("Capture") {
                HStack(spacing: 8) {
                    CaptureTile(symbol: "rectangle.dashed", title: "Area", shortcut: "⌃⇧4") { services.captureArea() }
                    CaptureTile(symbol: "macwindow", title: "Window", shortcut: "⌃⇧6") { services.captureWindow() }
                    CaptureTile(symbol: "rectangle.inset.filled", title: "Screen", shortcut: "⌃⇧3") { services.captureScreen() }
                        .contextMenu {
                            Button("Capture in 3 seconds") { services.captureScreen(after: 3) }
                            Button("Capture in 5 seconds") { services.captureScreen(after: 5) }
                            Button("Capture in 10 seconds") { services.captureScreen(after: 10) }
                        }
                }
            }

            section("Record") {
                if services.isRecording {
                    recordingBar
                } else {
                    HStack(spacing: 8) {
                        CaptureTile(symbol: "record.circle", title: "Area", shortcut: "⌃⇧5", tint: Brand.vermillion) { services.recordArea() }
                        CaptureTile(symbol: "rectangle.inset.filled.badge.record", title: "Screen", shortcut: nil, tint: Brand.vermillion) { services.recordScreen() }
                    }
                }
            }

            section("Tools") {
                VStack(spacing: 0) {
                    ToolRow(symbol: "text.viewfinder", title: "Copy Text (OCR)", shortcut: "⌃⇧2", pro: !license.isPro) {
                        services.copyTextFromScreen()
                    }
                    hairline
                    ToolRow(symbol: "qrcode.viewfinder", title: "Scan QR Code", shortcut: nil, pro: !license.isPro) {
                        services.scanQRCode()
                    }
                    hairline
                    ToolRow(symbol: "eyedropper", title: "Pick Color from Screen", shortcut: "⌃⇧C", pro: false) {
                        services.pickColor()
                    }
                    hairline
                    ToolRow(symbol: "pin", title: "Pin Last Screenshot", shortcut: "⌃⇧P", pro: !license.isPro) {
                        services.pinLastCapture()
                    }
                    hairline
                    ToolRow(symbol: "pencil.tip.crop.circle", title: "Annotate Last Screenshot", shortcut: "⌃⇧E", pro: false) {
                        services.annotateLastCapture()
                    }
                    hairline
                    ToolRow(symbol: "clock.arrow.circlepath", title: "Capture History", shortcut: "⌃⇧H", pro: false) {
                        services.openHistory()
                    }
                    hairline
                    ToolRow(
                        symbol: services.desktopIconsHidden ? "eye" : "eye.slash",
                        title: services.desktopIconsHidden ? "Show Desktop Icons" : "Hide Desktop Icons",
                        shortcut: nil, pro: false
                    ) {
                        services.toggleDesktopIcons()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 9).fill(Brand.cream)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.hairline, lineWidth: 1)
                )
            }

            if !services.recents.isEmpty {
                section("Recent") { recentsStrip }
            }

            Rectangle().fill(Brand.hairline).frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: 324)
        .background(Brand.paper)
        .environment(\.colorScheme, .light)
        .foregroundStyle(Brand.ink)
    }

    private var hairline: some View {
        Rectangle().fill(Brand.hairline.opacity(0.5)).frame(height: 1).padding(.leading, 34)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            LogoMark()
            Text("SnapBar")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Brand.ink)

            statusBadge

            Spacer()

            HeaderButton(symbol: "gearshape", help: "Settings") {
                services.closePopover?()
                SettingsWindowController.shared.show()
            }
            HeaderButton(symbol: "power", help: "Quit SnapBar") {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if license.hasLicense {
            badgeView("PRO", fill: Brand.vermillion, textColor: .white)
        } else if license.trialActive {
            badgeView("TRIAL · \(license.trialDaysLeft)D", fill: Brand.ink.opacity(0.08), textColor: Brand.graphite)
        } else {
            badgeView("FREE", fill: Brand.ink.opacity(0.08), textColor: Brand.graphite)
        }
    }

    private func badgeView(_ text: String, fill: Color, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(fill))
            .foregroundStyle(textColor)
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Brand.graphite)
                .padding(.leading, 2)
            content()
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            PulsingDot()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedString)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Brand.ink)
            }
            Text("REC")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Brand.vermillion)
            Spacer()
            Button {
                services.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.vermillion)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Brand.cream))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.vermillion.opacity(0.55), lineWidth: 1.5))
    }

    private var elapsedString: String {
        let seconds = Int(Date().timeIntervalSince(services.capture.recordingStartDate ?? Date()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Recents

    private var recentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(services.recents.prefix(10), id: \.self) { url in
                    RecentThumb(url: url)
                        .environmentObject(services)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                services.openSaveFolder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text("OPEN FOLDER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundStyle(Brand.graphite)
            }
            .buttonStyle(.plain)

            Spacer()

            if !license.hasLicense {
                Button {
                    services.closePopover?()
                    UpgradeWindowController.shared.show()
                } label: {
                    Text("UPGRADE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Brand.vermillion))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.ink, lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Text("V1.6")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.graphite.opacity(0.7))
            }
        }
    }
}

// MARK: - Components

/// The brand mark: viewfinder brackets + keeper dot on a cream chip.
private struct LogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Brand.cream)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Brand.hairline, lineWidth: 1)
            Image(systemName: "viewfinder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.ink)
            Circle()
                .fill(Brand.vermillion)
                .frame(width: 4.5, height: 4.5)
        }
        .frame(width: 25, height: 25)
    }
}

private struct CaptureTile: View {
    let symbol: String
    let title: String
    let shortcut: String?
    var tint: Color = Brand.ink
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(height: 19)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.ink)
                Text(shortcut ?? " ")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.graphite.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovering ? Brand.cream : Brand.cream.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(hovering ? Brand.ink.opacity(0.55) : Brand.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ToolRow: View {
    let symbol: String
    let title: String
    let shortcut: String?
    let pro: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(Brand.graphite)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.ink)
                Spacer()
                if pro {
                    Text("PRO")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .padding(.horizontal, 5.5).padding(.vertical, 1.5)
                        .background(Capsule().fill(Brand.vermillion))
                        .foregroundStyle(.white)
                }
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Brand.graphite.opacity(0.8))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(hovering ? Brand.ink.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentThumb: View {
    let url: URL
    @EnvironmentObject var services: AppServices

    @State private var hovering = false

    private var isMovie: Bool { url.pathExtension.lowercased() == "mov" }

    var body: some View {
        Group {
            if let thumb = services.thumbnail(for: url) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Brand.cream
                    Image(systemName: isMovie ? "film" : "photo")
                        .foregroundStyle(Brand.graphite)
                }
            }
        }
        .frame(width: 62, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hovering ? Brand.vermillion : Brand.hairline, lineWidth: hovering ? 1.5 : 1)
        )
        .onHover { hovering = $0 }
        .onTapGesture { services.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { services.open(url) }
            if isMovie {
                Button("Edit Clip…") { services.editClip(url) }
            } else {
                Button("Annotate…") { services.annotate(url) }
                Button("Pin to Screen") { services.pin(url) }
            }
            Button("Copy") { services.copyImage(url) }
            Button("Reveal in Finder") { services.reveal(url) }
        }
        .help(url.lastPathComponent)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.graphite)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Brand.cream : .clear))
                .overlay(Circle().strokeBorder(hovering ? Brand.hairline : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Brand.vermillion)
            .frame(width: 9, height: 9)
            .opacity(pulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
