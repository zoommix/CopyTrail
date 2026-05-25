import AppKit

final class StatusItemController {
    let statusItem: NSStatusItem

    var onClick: ((NSStatusBarButton) -> Void)?

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
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        onClick?(button)
    }
}
