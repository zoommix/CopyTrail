import AppKit
import Combine
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: Config!
    private var history: HistoryStore!
    private var watcher: ClipboardWatcher!
    private var historyMenu: HistoryMenu!
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

        watcher = ClipboardWatcher { [weak self] text in
            self?.history.add(text)
        }
        watcher.start()

        // Seed with whatever is currently on the clipboard so first-open
        // isn't empty.
        if let existing = NSPasteboard.general.string(forType: .string), !existing.isEmpty {
            history.add(existing)
        }

        historyMenu = HistoryMenu(store: history)
        historyMenu.onRestore = { [weak self] entry in
            self?.watcher.write(entry.text)
        }
        historyMenu.onSettings = { [weak self] in self?.showSettings() }
        historyMenu.onQuit = { NSApp.terminate(nil) }

        statusItem = StatusItemController(menu: historyMenu.menu)

        KeyboardShortcuts.onKeyDown(for: .showCopyTrail) { [weak self] in
            self?.openMenu()
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

    /// Programmatically opens the status-item menu, used by the global hotkey.
    private func openMenu() {
        guard let button = statusItem.statusItem.button else { return }
        // performClick triggers the same menu-open path as a real left-click,
        // so menuWillOpen fires and our filter resets correctly.
        button.performClick(nil)
    }
}
