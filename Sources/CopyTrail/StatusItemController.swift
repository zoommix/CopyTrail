import AppKit

final class StatusItemController {
    let statusItem: NSStatusItem

    init(menu: NSMenu) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "CopyTrail"
            )
            image?.isTemplate = true
            button.image = image
        }

        statusItem.menu = menu
    }
}
