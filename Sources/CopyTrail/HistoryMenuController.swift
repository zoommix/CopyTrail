import AppKit
import ImageIO

private extension NSEvent {
    /// ⌦ or ⌥⌫. Plain ⌫ is swallowed by NSMenu's type-select while tracking.
    var isDeleteKey: Bool {
        keyCode == 117 || (keyCode == 51
            && modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .option)
    }
}

/// NSMenu that reports Delete / Forward-delete presses while it is tracking.
final class HistoryMenu: NSMenu {
    var onDelete: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.isDeleteKey, onDelete?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Native NSMenu showing clipboard history. Rebuilt lazily each time it opens.
final class HistoryMenuController: NSObject, NSMenuDelegate {
    private let store: HistoryStore
    private let onRestore: (HistoryEntry) -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    let menu = HistoryMenu()
    private var keyMonitor: Any?
    private var lastHighlighted: NSMenuItem?

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
        menu.onDelete = { [weak self] in self?.removeHighlighted() ?? false }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let entries = store.entries
        if !entries.isEmpty {
            let hint = NSMenuItem(title: "Press ⌦ or ⌥⌫ to remove highlighted item", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
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
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit CopyTrail", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.isDeleteKey { return self.removeHighlighted() ? nil : event }
            if event.keyCode == 125 || event.keyCode == 126 {
                self.advanceHighlight(down: event.keyCode == 125)
            }
            return event
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Removes the item under the cursor / keyboard highlight. Returns true if handled.
    fileprivate func removeHighlighted() -> Bool {
        // AppKit may report no highlight (or a stale one), so fall back to the cached item.
        let entries = menu.items.filter { $0.representedObject is HistoryEntry.ID }
        guard let item = [menu.highlightedItem, lastHighlighted].compactMap({ $0 }).first(where: entries.contains),
              let id = item.representedObject as? HistoryEntry.ID,
              let index = entries.firstIndex(of: item) else { return false }
        store.remove(id)
        // Rebuild in place, then re-highlight the neighbour so arrow keys keep
        // working from here instead of restarting at the top/bottom.
        menuNeedsUpdate(menu)
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

    private func advanceHighlight(down: Bool) {
        let start = (lastHighlighted ?? menu.highlightedItem).map(menu.index(of:)) ?? (down ? -1 : menu.numberOfItems)
        let step = down ? 1 : -1
        var index = start + step
        while index >= 0 && index < menu.numberOfItems {
            guard let item = menu.item(at: index) else { break }
            if item.isEnabled && !item.isHidden && !item.isSeparatorItem {
                lastHighlighted = item
                return
            }
            index += step
        }
        lastHighlighted = nil
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
