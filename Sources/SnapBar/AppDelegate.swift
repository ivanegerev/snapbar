import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private var statusController: StatusItemController?
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        _ = LicenseManager.shared // stamps first-launch date for the trial
        installMainMenu()
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
        // A login-item app runs for weeks; the 0.9-day gate inside keeps this to one request a day.
        let updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.services.checkForUpdatesIfDue()
        }
        updateTimer.tolerance = 600
    }

    /// Never visible for an accessory app, but AppKit only routes ⌘C/⌘V/⌘Z/⌘W/⌘Q
    /// to text fields and windows through the main menu's key equivalents.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            for item in items { menu.addItem(item) }
            let host = NSMenuItem()
            host.submenu = menu
            mainMenu.addItem(host)
        }
        func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        submenu("SnapBar", [
            item("About SnapBar", #selector(showAbout), "", target: self),
            item("Settings…", #selector(showSettings), ",", target: self),
            .separator(),
            item("Quit SnapBar", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() { AboutWindowController.shared.show() }
    @objc private func showSettings() { SettingsWindowController.shared.show() }

    /// "Open With → SnapBar" from Finder: images land in the markup editor,
    /// movies in the clip trimmer.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
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
            self?.services.captureScreen()
        }
        hotkeys.register(keyCode: kVK_ANSI_4, modifiers: ctrlShift) { [weak self] in
            self?.services.captureArea()
        }
        hotkeys.register(keyCode: kVK_ANSI_6, modifiers: ctrlShift) { [weak self] in
            self?.services.captureWindow()
        }
        hotkeys.register(keyCode: kVK_ANSI_5, modifiers: ctrlShift) { [weak self] in
            guard let self else { return }
            if self.services.capture.isRecording {
                self.services.stopRecording()
            } else {
                self.services.recordArea()
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

    /// Unsaved markup cancels the quit and shows its Save sheet; quit again once it's handled.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditorWindowController.closeDirtyForQuit() ? .terminateCancel : .terminateNow
    }

    /// Every quit path (menu, ⌘Q, popover, logout) lands here. The main queue never
    /// runs again after this returns, so the recording is finalized synchronously.
    func applicationWillTerminate(_ notification: Notification) {
        services.capture.stopRecordingAndWait()
    }
}
