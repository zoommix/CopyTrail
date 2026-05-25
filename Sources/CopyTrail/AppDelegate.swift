import AppKit
import Combine
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: Config!
    private var history: HistoryStore!
    private var watcher: ClipboardWatcher!
    private var popover: HistoryPopoverController!
    private var statusItem: StatusItemController!
    private var settingsWC: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        config = Config()
        history = HistoryStore(maxLen: config.maxHistory)

        config.$maxHistory
            .dropFirst()
            .sink { [weak self] n in self?.history.setMax(n) }
            .store(in: &cancellables)

        watcher = ClipboardWatcher { [weak self] item in
            self?.history.add(item)
        }
        watcher.start()

        // Seed history with whatever's currently on the clipboard so the
        // popover isn't empty on first open.
        if let existing = NSPasteboard.general.string(forType: .string), !existing.isEmpty {
            history.add(.text(existing))
        } else if let png = NSPasteboard.general.data(forType: .png) {
            history.add(.image(pngData: png))
        }

        popover = HistoryPopoverController(store: history) { [weak self] entry in
            self?.restore(entry)
        }

        statusItem = StatusItemController()
        statusItem.onPrimaryClick = { [weak self] button in
            self?.popover.toggle(relativeTo: button)
        }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.onQuit = { NSApp.terminate(nil) }

        KeyboardShortcuts.onKeyDown(for: .showCopyTrail) { [weak self] in
            self?.toggleFromHotkey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        history?.flush()
    }

    private func showSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(config: config)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.showCentered()
    }

    private func restore(_ entry: HistoryEntry) {
        switch entry.kind {
        case .text:
            watcher.writeText(entry.text ?? "")
        case .image:
            guard
                let url = history.imageURL(for: entry),
                let data = try? Data(contentsOf: url)
            else { return }
            watcher.writeImage(pngData: data)
        }
    }

    private func toggleFromHotkey() {
        guard let button = statusItem.statusItem.button else { return }
        popover.toggle(relativeTo: button)
    }
}
