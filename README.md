# CopyTrail

<p align="center">
  <img width="388" height="365" align="top" alt="image" src="https://github.com/user-attachments/assets/e50b2188-7a77-475f-a797-565ac8aa264b" />
  &nbsp;&nbsp;
  <img width="396" height="464" align="top" alt="image" src="https://github.com/user-attachments/assets/5b71dd16-09e3-4067-9d8a-202e0ef81da3" />

  <img width="666" height="372" alt="image" src="https://github.com/user-attachments/assets/c393d0eb-3fcd-4200-badf-77bb4ebadd4a" />
</p>

A small clipboard history menu-bar app for macOS. Watches the system pasteboard, keeps a configurable backlog of past entries (text and images), and lets you search and restore any of them via a native dropdown.

## Features

- Lives in the menu bar; click for a fully native `NSMenu` of your history.
- The search field is focused when the menu opens — just start typing. Search is case-insensitive and matches anywhere in the text (not just the start); ⌫ edits the query, Esc clears it (a second Esc closes the menu). Focus stays in the search field while typing; ↓ moves into the list, ↑ on the first row returns to search, and Return in the search field restores the top match.
- Click or press Return to restore an entry; Esc to dismiss.
- Press **⌦** or **⌥⌫** while an item is highlighted to remove it (focus moves to the next item, so you can keep deleting with the keyboard); hover an item for a full-text tooltip.
- Hold **⇧ Shift** on a highlighted item to preview its full text or image in a panel beside the menu; ↑/↓ keep working while Shift is held.
- `⌘1`–`⌘9`, `⌘0` to restore the first ten visible entries directly.
- Configurable global hotkey (default `⌃Space`) opens the menu.
- Handles both text and PNG/TIFF image clipboard payloads (images are stored on disk and shown with a thumbnail in the list).
- Configurable max history (10 – 100 000 entries), max image size (0 – 100 MB; `0` disables image capture) and preview width (200 – 1200 px).
- Per-item removal (⌦ or ⌥⌫) and a "Clear history…" action in Settings.
- Optional **Launch at startup** toggle (uses `SMAppService`).

## Requirements

- macOS 14 (Sonoma) or newer
- Full Xcode (Swift 5.9+). The default universal build needs `xcbuild`, and the KeyboardShortcuts dependency needs the SwiftUI preview macros. Both ship only with Xcode, not with the Command Line Tools.

## Build & install

```sh
./build-app.sh
```

This builds the executable, assembles `CopyTrail.app`, ad-hoc-signs it, and copies it to `/Applications/CopyTrail.app`.

If the build fails with `xcbuild executable … does not exist` or `plugin for module 'PreviewsMacros' not found`, the active developer directory is the Command Line Tools (check with `xcode-select -p`). Point it at Xcode, either permanently:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

or for a single build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build-app.sh
```

`UNIVERSAL=0 ./build-app.sh` builds for the host architecture only (faster, and doesn't need `xcbuild`).

To run:

```sh
open /Applications/CopyTrail.app
```

First time you open it, macOS will ask for **Accessibility** permission so the global hotkey can fire (System Settings → Privacy & Security → Accessibility). The **Launch at startup** toggle uses System Settings → General → Login Items.

For iterative development without the bundle/install step:

```sh
swift run
```

## Where things are stored

- `~/Library/Application Support/CopyTrail/config.json` — `maxHistory`, `maxImageMB`, `previewWidth`
- `~/Library/Application Support/CopyTrail/history.json` — entry list
- `~/Library/Application Support/CopyTrail/images/<sha>.png` — image payloads (deduplicated by SHA-256)

Login-item state is managed by `SMAppService` and lives in macOS, not in CopyTrail's own config.

## Project layout

```
Package.swift
build-app.sh
Sources/CopyTrail/
  main.swift                       NSApplication entry
  AppDelegate.swift                wires everything together
  StatusItemController.swift       NSStatusItem + menu
  HistoryMenuController.swift      native NSMenu with history items
  PreviewPanelController.swift     Shift-preview panel beside the menu
  PreviewContentView.swift         SwiftUI text/image preview content
  VisualEffectView.swift           NSVisualEffectView wrapper for the preview background
  ClipboardWatcher.swift           NSPasteboard.changeCount poller
  HistoryStore.swift               ObservableObject; on-disk JSON + images
  Config.swift                     persisted preferences
  Paths.swift                      ~/Library/Application Support helpers
  SettingsView.swift               SwiftUI settings form
  SettingsWindowController.swift   hosts SettingsView
  Shortcuts.swift                  KeyboardShortcuts.Name extension
  LoginItem.swift                  SMAppService wrapper
  Resources/
    Info.plist                     LSUIElement = true, embedded via linker
    AppIcon.icns                   bundle icon, copied by build-app.sh
```

## Dependencies

- [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey recorder + persistence

That's the only third-party dependency. Everything else is AppKit / SwiftUI / Foundation.

## License

MIT — see [LICENSE](LICENSE).
