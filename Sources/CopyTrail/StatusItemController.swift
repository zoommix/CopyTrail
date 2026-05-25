import AppKit

final class StatusItemController {
    let statusItem: NSStatusItem
    private let contextMenu = NSMenu()

    var onPrimaryClick: ((NSStatusBarButton) -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "CopyTrail"
            )
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(emitSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        contextMenu.addItem(settingsItem)

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit CopyTrail",
            action: #selector(emitQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp ||
            (event?.modifierFlags.contains(.control) ?? false)

        if isRight {
            statusItem.menu = contextMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            onPrimaryClick?(button)
        }
    }

    @objc private func emitSettings() { onSettings?() }
    @objc private func emitQuit() { onQuit?() }
}
