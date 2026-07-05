import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private var statusController: StatusItemController?
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        _ = LicenseManager.shared // stamps first-launch date for the trial
        statusController = StatusItemController(services: services)
        registerHotkeys()

        // Walk the user through Screen Recording permission up front instead
        // of letting the first capture fail silently.
        if !ScreenPermission.granted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PermissionWindowController.shared.show()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WelcomeWindowController.shared.showIfNeeded()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.services.runAutoCleanup()
            self?.services.checkForUpdatesIfDue()
        }
    }

    /// "Open With → SnapBar" from Finder: images land in the markup editor,
    /// movies in the clip trimmer.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if ["mov", "mp4"].contains(url.pathExtension.lowercased()) {
                ClipEditorWindowController.open(url)
            } else {
                EditorWindowController.open(url)
            }
        }
    }

    /// ⌃⇧2/3/4/5/6 — deliberately Control instead of Command so they mirror the
    /// system's ⇧⌘3/4/5 without conflicting with them.
    private func registerHotkeys() {
        let ctrlShift = controlKey | shiftKey
        hotkeys.register(keyCode: kVK_ANSI_3, modifiers: ctrlShift) { [weak self] in
            self?.services.capture.captureStill(.screen)
        }
        hotkeys.register(keyCode: kVK_ANSI_4, modifiers: ctrlShift) { [weak self] in
            self?.services.capture.captureStill(.area)
        }
        hotkeys.register(keyCode: kVK_ANSI_6, modifiers: ctrlShift) { [weak self] in
            self?.services.capture.captureStill(.window)
        }
        hotkeys.register(keyCode: kVK_ANSI_5, modifiers: ctrlShift) { [weak self] in
            guard let self else { return }
            if self.services.capture.isRecording {
                self.services.capture.stopRecording()
            } else {
                self.services.capture.startRecording(.area)
            }
        }
        hotkeys.register(keyCode: kVK_ANSI_2, modifiers: ctrlShift) { [weak self] in
            self?.services.copyTextFromScreen()
        }
        hotkeys.register(keyCode: kVK_ANSI_C, modifiers: ctrlShift) { [weak self] in
            self?.services.pickColor()
        }
        hotkeys.register(keyCode: kVK_ANSI_P, modifiers: ctrlShift) { [weak self] in
            self?.services.pinLastCapture()
        }
        hotkeys.register(keyCode: kVK_ANSI_E, modifiers: ctrlShift) { [weak self] in
            self?.services.annotateLastCapture()
        }
        hotkeys.register(keyCode: kVK_ANSI_H, modifiers: ctrlShift) { [weak self] in
            self?.services.openHistory()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if services.capture.isRecording {
            services.capture.stopRecording()
        }
    }
}
