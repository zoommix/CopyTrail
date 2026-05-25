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

    init(store: HistoryStore, onRestore: @escaping (HistoryEntry) -> Void) {
        self.store = store
        self.onRestore = onRestore

        popover.behavior = .transient
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
        rebuildContent() // re-create so SearchView's onAppear refocuses the field
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
