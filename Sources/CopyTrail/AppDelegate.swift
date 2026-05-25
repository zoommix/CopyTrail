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

        watcher = ClipboardWatcher { [weak self] text in
            self?.history.add(text)
        }
        watcher.start()

        if let existing = NSPasteboard.general.string(forType: .string), !existing.isEmpty {
            history.add(existing)
        }

        popover = HistoryPopoverController(store: history) { [weak self] entry in
            self?.watcher.write(entry.text)
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

    private func toggleFromHotkey() {
        guard let button = statusItem.statusItem.button else { return }
        popover.toggle(relativeTo: button)
    }
}
