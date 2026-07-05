import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @AppStorage("saveDir") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("format") private var format = "png"
    @AppStorage("copyToClipboard") private var copyToClipboard = false
    @AppStorage("showThumbnail") private var showThumbnail = true
    @AppStorage("openEditorAfterCapture") private var openEditorAfterCapture = true
    @AppStorage("playSound") private var playSound = true
    @AppStorage("windowShadow") private var windowShadow = true
    @AppStorage("showCursor") private var showCursor = true
    @AppStorage("delaySeconds") private var delaySeconds = 0
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("showClicks") private var showClicks = false
    @AppStorage("screenshotPrefix") private var screenshotPrefix = "Screenshot"
    @AppStorage("recordingPrefix") private var recordingPrefix = "Screen Recording"
    @AppStorage("autoCleanupDays") private var autoCleanupDays = 0
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(abbreviatedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                    }
                }
                Picker("Image format", selection: $format) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                    Text("HEIC").tag("heic")
                    Text("PDF").tag("pdf")
                    Text("TIFF").tag("tiff")
                }
                TextField("Screenshot file name", text: $screenshotPrefix, prompt: Text("Screenshot"))
                TextField("Recording file name", text: $recordingPrefix, prompt: Text("Screen Recording"))
                Picker("Auto-tidy old captures", selection: $autoCleanupDays) {
                    Text("Never").tag(0)
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                    Text("After 90 days").tag(90)
                }
                if autoCleanupDays > 0 {
                    Text("Captures older than \(autoCleanupDays) days are moved to the Trash at launch — only files matching the names above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Also copy screenshots to clipboard", isOn: $copyToClipboard)
                Toggle("Open editor after each capture", isOn: $openEditorAfterCapture)
                Toggle("Show floating thumbnail after capture", isOn: $showThumbnail)
                if openEditorAfterCapture {
                    Text("The editor replaces the thumbnail while enabled — screenshots open in markup, recordings in the clip trimmer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Screenshots") {
                Picker("Self-timer", selection: $delaySeconds) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                Toggle("Include window shadow", isOn: $windowShadow)
                Toggle("Show mouse pointer (full-screen shots)", isOn: $showCursor)
            }

            Section("Recordings") {
                Toggle("Record microphone audio", isOn: $recordMicrophone)
                Toggle("Highlight mouse clicks", isOn: $showClicks)
            }

            Section("SnapBar Pro") {
                LabeledContent("License") {
                    HStack(spacing: 8) {
                        Text(license.statusLabel)
                            .foregroundStyle(license.hasLicense ? .green : .secondary)
                        Button("Manage…") { UpgradeWindowController.shared.show() }
                    }
                }
            }

            Section("Shortcuts") {
                LabeledContent("Capture") { Text("⌃⇧4 area · ⌃⇧6 window · ⌃⇧3 screen").foregroundStyle(.secondary) }
                LabeledContent("Record") { Text("⌃⇧5 start / stop").foregroundStyle(.secondary) }
                LabeledContent("Tools") { Text("⌃⇧2 OCR · ⌃⇧C color · ⌃⇧P pin · ⌃⇧E annotate · ⌃⇧H history").foregroundStyle(.secondary) }
            }

            Section("General") {
                Toggle("Play capture sound", isOn: $playSound)
                Toggle("Check for updates daily", isOn: $autoCheckUpdates)
                Toggle("Launch SnapBar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private var abbreviatedPath: String {
        (saveDir as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Prefs.saveDirURL
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            saveDir = url.path
        }
    }
}

/// Owns the single settings window.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "SnapBar Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
