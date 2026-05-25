import AppKit

/// HistoryMenu owns the NSMenu attached to the status item. It renders a
/// native macOS dropdown with:
///   - a header label that doubles as a live search prompt,
///   - one item per history entry (⌘0–⌘9 on the first ten visible matches),
///   - Settings / Quit footer items.
///
/// Type-to-filter is implemented by attaching a local NSEvent monitor while
/// the menu is open and consuming alphanumeric / backspace keystrokes — the
/// native NSMenu "type to select" behaviour is therefore bypassed.
final class HistoryMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    var onRestore: ((HistoryEntry) -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private weak var store: HistoryStore?
    private let headerView = HeaderMenuItemView()
    private var headerItem: NSMenuItem!
    private var filter: String = ""
    private var eventMonitor: Any?

    init(store: HistoryStore) {
        self.store = store
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false

        headerItem = NSMenuItem()
        headerItem.view = headerView
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Static footer is rebuilt every time we refresh, so we don't add
        // anything else here.
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        filter = ""
        refresh()
        installEventMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        uninstallEventMonitor()
        filter = ""
    }

    // MARK: Building items

    private func refresh() {
        headerView.setPrompt(filter: filter)

        // Remove everything except the header item.
        while menu.items.count > 1 {
            menu.removeItem(at: 1)
        }

        let entries = store?.search(filter) ?? []

        if entries.isEmpty {
            let placeholder = NSMenuItem(
                title: filter.isEmpty ? "No clipboard history yet" : "No matches",
                action: nil,
                keyEquivalent: ""
            )
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for (idx, entry) in entries.enumerated() {
                let keyEquivalent: String
                if idx < 10 {
                    keyEquivalent = "\((idx + 1) % 10)" // ⌘1…⌘9, then ⌘0
                } else {
                    keyEquivalent = ""
                }
                let item = NSMenuItem(
                    title: entry.preview,
                    action: #selector(restore(_:)),
                    keyEquivalent: keyEquivalent
                )
                item.keyEquivalentModifierMask = [.command]
                item.target = self
                item.representedObject = entry
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit CopyTrail",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func restore(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? HistoryEntry else { return }
        onRestore?(entry)
    }

    @objc private func showSettings() { onSettings?() }
    @objc private func quit() { onQuit?() }

    // MARK: Type-to-filter event monitor

    private func installEventMonitor() {
        uninstallEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func uninstallEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Let NSMenu handle navigation, selection, and command shortcuts.
        switch event.keyCode {
        case 36, 76, 53, 125, 126, 123, 124: // return, enter, esc, down, up, left, right
            return event
        default:
            break
        }
        if event.modifierFlags.contains(.command) {
            return event
        }

        // Backspace removes the last filter character.
        if event.keyCode == 51 {
            if !filter.isEmpty {
                filter.removeLast()
                refresh()
                return nil
            }
            return event
        }

        guard
            let chars = event.charactersIgnoringModifiers,
            let scalar = chars.unicodeScalars.first,
            isAcceptableFilterChar(scalar)
        else {
            return event
        }
        filter.append(chars)
        refresh()
        return nil
    }

    private func isAcceptableFilterChar(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.alphanumerics.contains(scalar) { return true }
        if scalar == " " || scalar == "-" || scalar == "_" ||
           scalar == "." || scalar == "/" || scalar == ":" { return true }
        return false
    }
}

/// Header NSMenuItem view: a single-line label that shows the search prompt
/// or the current filter text.
final class HeaderMenuItemView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        setupSubviews()
        setPrompt(filter: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
        setPrompt(filter: "")
    }

    private func setupSubviews() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setPrompt(filter: String) {
        if filter.isEmpty {
            label.stringValue = "Select the clip you want to add to your clipboard"
        } else {
            label.stringValue = "Search: \(filter)"
        }
    }
}
