import AppKit
import SwiftUI
import Combine

/// Owns the menu bar item. Left-click opens the SwiftUI popover, right-click
/// shows a minimal context menu. While recording the icon turns into a red
/// dot with a live elapsed timer.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let services: AppServices
    private let popover = NSPopover()
    private var recordingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(services: AppServices) {
        self.services = services
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let hosting = NSHostingController(rootView: MenuPopoverView().environmentObject(services))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        // The popover is paper-themed; keep its chrome light regardless of system mode.
        popover.appearance = NSAppearance(named: .aqua)

        services.closePopover = { [weak self] in
            self?.popover.performClose(nil)
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateButton()

        services.$isRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recordingStateChanged() }
            .store(in: &cancellables)
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: button)
        } else {
            togglePopover(from: button)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About SnapBar", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let upgrade = NSMenuItem(title: "SnapBar Pro…", action: #selector(openUpgrade), keyEquivalent: "")
        upgrade.target = self
        menu.addItem(upgrade)
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let site = NSMenuItem(title: "Visit Website", action: #selector(openWebsite), keyEquivalent: "")
        site.target = self
        menu.addItem(site)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SnapBar", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func openUpgrade() { UpgradeWindowController.shared.show() }
    @objc private func openAbout() { AboutWindowController.shared.show() }
    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ivanegerev/snapbar/releases/latest")!)
    }
    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://ivanegerev.github.io/snapbar/")!)
    }
    @objc private func quit() {
        if services.capture.isRecording { services.capture.stopRecording() }
        NSApp.terminate(nil)
    }

    // MARK: - Recording indicator

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if services.capture.isRecording {
            button.image = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: "SnapBar — recording"
            )
            button.contentTintColor = .systemRed
            button.imagePosition = .imageLeft
        } else {
            button.image = Self.barIcon
            button.contentTintColor = nil
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// The brand mark as a menu bar template image: crop-corner brackets + dot.
    private static let barIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let frame = NSRect(x: 2, y: 2, width: 14, height: 14)
            let arm: CGFloat = 3.8
            NSColor.black.setStroke()
            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                (CGPoint(x: frame.minX, y: frame.maxY - arm), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX + arm, y: frame.maxY)),
                (CGPoint(x: frame.maxX - arm, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY - arm)),
                (CGPoint(x: frame.maxX, y: frame.minY + arm), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX - arm, y: frame.minY)),
                (CGPoint(x: frame.minX + arm, y: frame.minY), CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.minY + arm)),
            ]
            for (a, corner, b) in corners {
                let p = NSBezierPath()
                p.move(to: a)
                p.line(to: corner)
                p.line(to: b)
                p.lineWidth = 1.6
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
            NSColor.black.setFill()
            let r: CGFloat = 2.2
            NSBezierPath(ovalIn: NSRect(x: frame.midX - r, y: frame.midY - r, width: r * 2, height: r * 2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func recordingStateChanged() {
        updateButton()
        recordingTimer?.invalidate()
        recordingTimer = nil
        if services.capture.isRecording {
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateElapsed()
            }
            recordingTimer?.tolerance = 0.2
            updateElapsed()
        }
    }

    private func updateElapsed() {
        guard let start = services.capture.recordingStartDate, let button = statusItem.button else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        button.title = String(format: " %d:%02d", elapsed / 60, elapsed % 60)
    }
}
