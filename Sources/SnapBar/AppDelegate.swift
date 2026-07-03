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
    }

    func applicationWillTerminate(_ notification: Notification) {
        if services.capture.isRecording {
            services.capture.stopRecording()
        }
    }
}
