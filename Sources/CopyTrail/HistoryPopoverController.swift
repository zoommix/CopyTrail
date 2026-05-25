import AppKit
import SwiftUI

/// NSHostingController subclass that:
///   - propagates SwiftUI's intrinsic content size to the popover, so the
///     popover shrinks/grows to fit the search view as the user filters;
///   - forces its window to become key on appear so the embedded
///     NSSearchField can become first responder.
private final class FocusingHostingController<Root: View>: NSHostingController<Root> {
    override init(rootView: Root) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeKey()
    }
}

final class HistoryPopoverController {
    private let popover = NSPopover()
    private let store: HistoryStore
    private let onRestore: (HistoryEntry) -> Void

    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?

    init(store: HistoryStore, onRestore: @escaping (HistoryEntry) -> Void) {
        self.store = store
        self.onRestore = onRestore

        // .applicationDefined keeps the popover alive across spaces and in
        // fullscreen apps; we close it ourselves via a global mouse monitor
        // and via the search-field's Esc handler.
        popover.behavior = .applicationDefined
        popover.animates = false

        rebuildContent()
    }

    private func rebuildContent() {
        let view = SearchView(
            store: store,
            onRestore: { [weak self] entry in
                self?.onRestore(entry)
                self?.close()
            },
            onDismiss: { [weak self] in self?.close() }
        )
        popover.contentViewController = FocusingHostingController(rootView: view)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        rebuildContent()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if let window = popover.contentViewController?.view.window {
            // Make the popover visible on the fullscreen space we're currently on.
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.makeKey()
        }

        installDismissMonitors()
    }

    func close() {
        uninstallDismissMonitors()
        popover.performClose(nil)
    }

    // MARK: Dismissal

    private func installDismissMonitors() {
        uninstallDismissMonitors()

        // Click in another app's window → close. Local clicks (our own
        // status item, our own popover content) don't fire this monitor,
        // so the toggle button still works correctly.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }

        // Esc anywhere in our process → close. Backstop for fullscreen
        // contexts where the popover window doesn't reliably hold key
        // state, so the NSSearchField delegate's cancelOperation: path
        // may not fire.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.close()
                return nil
            }
            return event
        }
    }

    private func uninstallDismissMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
