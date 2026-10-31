import AppKit
import ImageIO

private extension NSEvent {
    var plainModifiers: NSEvent.ModifierFlags {
        modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
    }

    /// ⌦ or ⌥⌫ (plain ⌫ edits the search query).
    var isDeleteKey: Bool {
        keyCode == 117 || (keyCode == 51 && plainModifiers == .option)
    }
}

/// NSMenu that reports key presses while it is tracking (fallback path for
/// events that bypass `TrackingKeyMonitor`).
final class HistoryMenu: NSMenu {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyDown?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Pulls key events off the queue before NSMenu's tracking loop sees them, so
/// typing never falls through to NSMenu's type-select (approach used by
/// KeyboardShortcuts and Maccy). Unhandled events are re-posted.
private final class TrackingKeyMonitor {
    private var observer: CFRunLoopObserver?
    private let mode = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)

    func start(_ handler: @escaping (NSEvent) -> Bool) {
        stop()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeSources.rawValue, true, 0) { _, _ in
            // Drain first, then handle, so re-posted events aren't picked up again in this pass.
            // Drain every event type: a key-only mask makes mouse tracking in the menu lag.
            var events: [NSEvent] = []
            while let event = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) {
                events.append(event)
            }
            for event in events where !(event.type == .keyDown && handler(event)) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, mode)
        self.observer = observer
    }

    func stop() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, mode) }
        observer = nil
    }
}

/// Native NSMenu showing clipboard history with an always-focused search field.
final class HistoryMenuController: NSObject, NSMenuDelegate {
    private static let placeholderTag = 1001

    private let store: HistoryStore
    private let onRestore: (HistoryEntry) -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    let menu = HistoryMenu()
    private let keyMonitor = TrackingKeyMonitor()
    private var lastHighlighted: NSMenuItem?
    private var footerSeparator: NSMenuItem?
    private var query = ""
    private var lastKeyTime: TimeInterval = -1

    private lazy var searchField: NSSearchField = {
        let field = NSSearchField(frame: NSRect(x: 12, y: 3, width: 256, height: 22))
        field.placeholderString = "Type to search"
        field.autoresizingMask = [.width]
        field.target = self
        field.action = #selector(searchFieldChanged)
        return field
    }()

    private lazy var searchItem: NSMenuItem = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        container.autoresizingMask = [.width]
        container.addSubview(searchField)
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }()

    init(
        store: HistoryStore,
        onRestore: @escaping (HistoryEntry) -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.onRestore = onRestore
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.onKeyDown = { [weak self] in self?.handleKey($0) ?? false }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !store.entries.isEmpty {
            menu.addItem(searchItem)
            let hint = NSMenuItem(title: "Press ⌦ or ⌥⌫ to remove highlighted item", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }

        let footer = NSMenuItem.separator()
        footerSeparator = footer
        menu.addItem(footer)
        let settings = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit CopyTrail", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        reloadEntries()
    }

    /// Replaces only the history rows, leaving the search row in place so the
    /// field keeps focus while filtering.
    private func reloadEntries() {
        for item in menu.items where item.representedObject is HistoryEntry.ID || item.tag == Self.placeholderTag {
            menu.removeItem(item)
        }
        if searchField.stringValue != query { searchField.stringValue = query }
        moveCaretToEnd()
        guard let footerSeparator else { return }
        var index = menu.index(of: footerSeparator)

        let entries = store.search(query)
        if entries.isEmpty {
            let title = store.entries.isEmpty ? "No clipboard history yet" : "No matches"
            let empty = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.tag = Self.placeholderTag
            menu.insertItem(empty, at: index)
        }
        for (idx, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.preview, action: #selector(restore(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.toolTip = tooltip(for: entry)
            if idx < 10 {
                item.keyEquivalent = String((idx + 1) % 10)
                item.keyEquivalentModifierMask = .command
            }
            if entry.kind == .image, let url = store.imageURL(for: entry) {
                item.image = Self.thumbnail(at: url)
            }
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    @objc private func restore(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? HistoryEntry.ID,
              let entry = store.entries.first(where: { $0.id == id }) else { return }
        onRestore(entry)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let item { lastHighlighted = item }
    }

    func menuWillOpen(_ menu: NSMenu) {
        lastHighlighted = nil
        keyMonitor.start { [weak self] in self?.handleKey($0) ?? false }
        // Start with the search field focused and no row highlighted.
        RunLoop.main.perform(inModes: [.eventTracking]) { [weak self] in
            guard let self else { return }
            self.searchField.window?.makeFirstResponder(self.searchField)
            self.moveCaretToEnd()
            self.highlight(nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        keyMonitor.stop()
        query = ""
    }

    /// Keys may arrive via the monitor and the performKeyEquivalent fallback;
    /// the timestamp check stops one keystroke being applied twice.
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.timestamp == lastKeyTime { return true }
        guard processKey(event) else { return false }
        lastKeyTime = event.timestamp
        return true
    }

    /// The search field is focused while no row is highlighted; only ↑/↓ move
    /// focus, and typing always returns it to the search field.
    private func processKey(_ event: NSEvent) -> Bool {
        if event.isDeleteKey { return removeHighlighted() }
        guard !store.entries.isEmpty else { return false }
        let mods = event.plainModifiers
        if mods.isEmpty {
            switch event.keyCode {
            case 125, 126:  // ↓ ↑
                moveHighlight(down: event.keyCode == 125)
                return true
            case 36, 76:  // Return in search field: restore top match
                guard currentHighlight == nil else { return false }
                if let first = menu.items.first(where: { $0.representedObject is HistoryEntry.ID }) {
                    menu.cancelTracking()
                    restore(first)
                }
                return true
            case 51:  // ⌫
                if !query.isEmpty { query.removeLast(); applyQuery() }
                return true
            case 53 where !query.isEmpty:  // Esc clears before closing
                query = ""
                applyQuery()
                return true
            default: break
            }
        }
        guard mods.isSubset(of: .shift), let chars = event.characters, !chars.isEmpty,
              chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                  && !(0xF700...0xF8FF).contains($0.value) }) else { return false }
        query += chars
        applyQuery()
        return true
    }

    private var currentHighlight: NSMenuItem? {
        [menu.highlightedItem, lastHighlighted].compactMap { $0 }.first { menu.index(of: $0) >= 0 }
    }

    /// ↓ from the search field enters the list; ↑ on the first row returns to it.
    private func moveHighlight(down: Bool) {
        let rows = menu.items.filter { $0.isEnabled && !$0.isHidden && !$0.isSeparatorItem && $0.view == nil }
        guard let current = currentHighlight, let i = rows.firstIndex(of: current) else {
            if down { highlight(rows.first) }
            return
        }
        if down {
            if i + 1 < rows.count { highlight(rows[i + 1]) }
        } else {
            highlight(i == 0 ? nil : rows[i - 1])
        }
    }

    @objc private func searchFieldChanged() {
        guard searchField.stringValue != query else { return }
        query = searchField.stringValue
        applyQuery()
    }

    private func applyQuery() {
        reloadEntries()
        highlight(nil)  // typing keeps focus in the search field
    }

    private func moveCaretToEnd() {
        searchField.currentEditor()?.selectedRange = NSRange(location: (query as NSString).length, length: 0)
    }

    /// Removes the highlighted entry and highlights its neighbour. Returns true if handled.
    fileprivate func removeHighlighted() -> Bool {
        let entries = menu.items.filter { $0.representedObject is HistoryEntry.ID }
        guard let item = [menu.highlightedItem, lastHighlighted].compactMap({ $0 }).first(where: entries.contains),
              let id = item.representedObject as? HistoryEntry.ID,
              let index = entries.firstIndex(of: item) else { return false }
        store.remove(id)
        reloadEntries()
        let remaining = menu.items.filter { $0.representedObject is HistoryEntry.ID }
        highlight(remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)])
        return true
    }

    /// Highlights `item` via the private `highlightItem:` (used by other clipboard
    /// managers). Re-applied on the next run-loop pass since AppKit resets the
    /// highlight after the menu changes; cleared first so the update isn't skipped.
    private func highlight(_ item: NSMenuItem?) {
        let selector = NSSelectorFromString("highlightItem:")
        guard menu.responds(to: selector) else { return }
        let apply = { [weak self] in
            guard let self, item.map({ self.menu.index(of: $0) >= 0 }) ?? true else { return }
            self.menu.perform(selector, with: nil)
            if let item { self.menu.perform(selector, with: item) }
            self.lastHighlighted = item
        }
        apply()
        RunLoop.main.perform(inModes: [.eventTracking, .common], block: apply)
    }

    @objc private func settings() { onSettings() }
    @objc private func quit() { onQuit() }

    private func tooltip(for entry: HistoryEntry) -> String? {
        guard entry.kind == .text, let text = entry.text else { return nil }
        return String(text.prefix(1000))
    }

    private static func thumbnail(at url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 56,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        let scale = 28.0 / max(Double(cg.width), 1)
        img.size = NSSize(width: 28, height: max(Double(cg.height) * scale, 1))
        return img
    }
}
