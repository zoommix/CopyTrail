import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(config: Config) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTrail Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let root = SettingsView(config: config) { [weak self] in
            self?.close()
        }
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showCentered() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
