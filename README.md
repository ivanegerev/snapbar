# SnapBar

A polished macOS menu bar app for screenshots and screen recordings. Lives in your
menu bar, stays out of your way.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-1a1713)

**Website:** [ivanegerev.github.io/snapbar](https://ivanegerev.github.io/snapbar/) ·
**Download:** [latest release](https://github.com/ivanegerev/snapbar/releases/latest)

> First launch on a fresh Mac: right-click SnapBar.app → **Open** (the build is
> ad-hoc signed, not yet notarized).

## Features

- **Modern menu bar popover** — capture tiles, tools, a recent-captures strip and
  live recording state, all in one SwiftUI dropdown
- **Capture Area / Window / Full Screen** — native crosshair selection, optional
  window shadow, mouse pointer, and a self-timer
- **Record Selected Area / Entire Screen** — with optional microphone audio and
  click highlighting; the menu bar icon turns into a red recording indicator with a
  live elapsed timer
- **Annotation editor** — arrows, boxes, ellipses, highlighter, freehand, text and
  auto-numbered steps, with undo, copy and save
- **Copy Text (OCR)** ⌃⇧2 — select any region, Vision OCRs it to the clipboard *(Pro)*
- **Pin to screen** — float screenshots above all windows as references *(Pro)*
- **Beautify** — gradient background, padding, rounded corners, shadow — share-ready
  shots in one click *(Pro)*
- **Pixelate** sensitive info in the editor *(Pro)*
- **Hide desktop icons** toggle for clean recordings
- **Capture History** ⌃⇧H — searchable grid of every capture with annotate /
  pin / copy / trash
- **Redact** (solid black) and **Crop** tools in the editor, plus zoom (⌘+/−/0)
- **Clip editor** for recordings — QuickTime-style trim + GIF export *(Pro)*
- **Pick Color from Screen** ⌃⇧C — system eyedropper, hex to clipboard
- **Auto-tidy** — optionally trash captures older than 7/30/90 days
- Custom file name prefixes, daily update check, "Open With SnapBar" from Finder
- **Floating thumbnail** after every capture — click to open, hover for quick
  actions (annotate / pin / copy), or drag it straight into Slack, Mail, Figma
- **Clipboard copy**, configurable save folder, PNG/JPEG/HEIC/PDF/TIFF formats
- **Launch at login**, capture sound toggle, and more in Settings

## SnapBar Pro

Full 7-day trial on first launch. After that, Pro tools unlock with a license key —
$14.99 one-time or $1.99/month (both issue the same key format). Keys are validated
offline (`LicenseManager.swift`); generate dev keys with
`swift scripts/make-license.swift`. The Buy buttons point at placeholder
`snapbar.app/buy/*` URLs — wire them to a Paddle / Lemon Squeezy / Stripe checkout
that emails keys, and optionally verify keys against that API in
`LicenseManager.activate`.

## Website

A ready-to-deploy landing page lives in `website/index.html` (features, pricing,
FAQ). Serve it locally with `python3 -m http.server --directory website`.

## Brand

The visual identity ("Contact Sheet" — paper, ink, one vermillion accent, mono
spec labels, grease-pencil keeper circles) is documented in [BRAND.md](BRAND.md).
The app icon is generated from the same mark by `scripts/make-icon.swift`.

## Global hotkeys

Control+Shift mirrors the system's ⇧⌘3/4/5 without conflicting with it:

| Hotkey | Action |
|--------|--------|
| ⌃⇧3 | Capture full screen |
| ⌃⇧4 | Capture area |
| ⌃⇧6 | Capture window |
| ⌃⇧5 | Start area recording / stop recording |
| ⌃⇧2 | Copy text from screen (OCR, Pro) |

## Building

Requires Xcode (or the command line tools) on macOS 13+.

```sh
scripts/build-app.sh        # builds dist/SnapBar.app (release, ad-hoc signed)
open dist/SnapBar.app
```

For development: `swift build && .build/debug/SnapBar` (some features like
launch-at-login need the real .app bundle).

## First run

macOS will ask for **Screen Recording** permission the first time you capture
(System Settings → Privacy & Security → Screen & System Audio Recording), and
**Microphone** permission if you enable mic audio for recordings. Grant them once
and you're set.

## Architecture

Pure Swift, no dependencies. AppKit menu bar app (`LSUIElement`) with a SwiftUI
settings window.

| File | Responsibility |
|------|----------------|
| `AppDelegate.swift` | Wiring + global hotkey bindings |
| `AppServices.swift` | Central hub: state for SwiftUI, shared actions, thumbnails |
| `StatusItemController.swift` | Menu bar icon, popover, recording timer |
| `MenuPopoverView.swift` | The SwiftUI menu bar dropdown UI |
| `CaptureManager.swift` | Drives `/usr/sbin/screencapture` for stills & video |
| `AnnotationEditor.swift` | Markup editor: tools, canvas, beautify, final render |
| `OCRManager.swift` | Copy-text-from-screen via Vision |
| `PinWindow.swift` | Floating pinned screenshots |
| `LicenseManager.swift` | Trial + license key validation (Pro) |
| `UpgradeWindow.swift` | Pricing / activation window |
| `HotkeyManager.swift` | Carbon global hotkeys (no accessibility permission needed) |
| `ThumbnailPanel.swift` | Floating post-capture preview (click / drag / hover actions) |
| `Toast.swift` | HUD notifications |
| `SettingsWindow.swift` | SwiftUI settings + launch-at-login (SMAppService) |
| `Prefs.swift` | UserDefaults-backed preferences & recents list |

Capture itself is delegated to the system's `screencapture` tool, which provides
the native selection UI, Retina/HDR handling, and the recording pipeline — the app
orchestrates it and owns everything around it (files, clipboard, thumbnails,
history, hotkeys).
