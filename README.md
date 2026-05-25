# CopyTrail

A small clipboard history menu-bar app for macOS. Watches the system pasteboard, keeps a configurable backlog of past entries (text and images), and lets you search and restore any of them via a native dropdown.

## Features

- Lives in the menu bar; left-click for the search dropdown, right-click for Settings / Quit.
- Real `NSSearchField` at the top of the popup with live substring filtering.
- Arrow keys / Return / mouse-click to restore an entry; Esc to dismiss.
- `⌘1`–`⌘9`, `⌘0` to restore the first ten visible entries directly.
- Configurable global hotkey (default `⌘⇧V`) toggles the popup.
- Handles both text and PNG/TIFF image clipboard payloads (images are stored on disk and shown with a thumbnail in the list).
- Configurable max history (10 – 100 000 entries) and max image size (0 – 100 MB; `0` disables image capture).
- Per-row delete (× appears on hover) and a "Clear history…" action in Settings.
- Optional **Launch at startup** toggle (uses `SMAppService`).
- Works in fullscreen apps — the popup repositions itself so the system menu-bar zone doesn't clip it.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode Command Line Tools (provides Swift 5.9+ and the macOS SDK)

## Build & install

```sh
./build-app.sh
```

This builds the executable, assembles `CopyTrail.app`, ad-hoc-signs it, and copies it to `/Applications/CopyTrail.app`.

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

- `~/Library/Application Support/CopyTrail/config.json` — `maxHistory`, `maxImageMB`
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
  StatusItemController.swift       NSStatusItem + left/right click routing
  HistoryPopoverController.swift   NSPopover with positioning hacks
  ClipboardWatcher.swift           NSPasteboard.changeCount poller
  HistoryStore.swift               ObservableObject; on-disk JSON + images
  Config.swift                     persisted preferences
  Paths.swift                      ~/Library/Application Support helpers
  SearchView.swift                 SwiftUI popup UI
  SearchField.swift                NSSearchField wrapper
  SettingsView.swift               SwiftUI settings form
  SettingsWindowController.swift   hosts SettingsView
  Shortcuts.swift                  KeyboardShortcuts.Name extension
  LoginItem.swift                  SMAppService wrapper
  VisualEffectView.swift           NSVisualEffectView wrapper
  Resources/
    Info.plist                     LSUIElement = true, embedded via linker
    AppIcon.icns                   bundle icon, copied by build-app.sh
```

## Dependencies

- [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey recorder + persistence

That's the only third-party dependency. Everything else is AppKit / SwiftUI / Foundation.

## License

MIT — see [LICENSE](LICENSE).
