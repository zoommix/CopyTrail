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
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?

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

        // .applicationDefined keeps the popover alive across spaces and in
        // fullscreen apps; we close it ourselves via a global mouse monitor
        // and via the search-field's Esc handler.
        popover.behavior = .applicationDefined
        popover.animates = false

        // Hide the anchor arrow. Public NSPopover has no flag for this;
        // KVC into the private "shouldHideAnchor" has been the standard
        // workaround for many years.
        popover.setValue(true, forKey: "shouldHideAnchor")

        rebuildContent()
    }

    private func rebuildContent() {
        let view = SearchView(
            store: store,
            onRestore: { [weak self] entry in
                self?.onRestore(entry)
                self?.close()
            },
            onDismiss: { [weak self] in self?.close() },
            onSettings: { [weak self] in
                self?.close()
                self?.onSettings()
            },
            onQuit: { [weak self] in
                self?.close()
                self?.onQuit()
            }
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

        // Sample fullscreen state BEFORE the popover shows: NSApp.activate
        // and popover.show both perturb the window list, so a check
        // afterwards is less reliable. Combined with the launch-time
        // CGWindowList warmup in AppDelegate, this is stable.
        let inFullscreen = Self.isAnyAppFullscreen()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        guard let window = popover.contentViewController?.view.window else {
            installDismissMonitors()
            return
        }

        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)

        if inFullscreen {
            // Defer to the next tick because in fullscreen NSPopover
            // sometimes settles its frame after layout, and we want the
            // user to never see the clipped intermediate position.
            window.alphaValue = 0
            DispatchQueue.main.async { [weak self] in
                guard
                    let self = self,
                    let window = self.popover.contentViewController?.view.window
                else { return }
                var frame = window.frame
                frame.origin.y -= Self.fullscreenBarInset()
                window.setFrame(frame, display: false)
                window.alphaValue = 1
                window.makeKey()
            }
        } else {
            // Normal mode: apply the small pull-up synchronously so the
            // popover appears immediately rather than one frame later.
            var frame = window.frame
            frame.origin.y += Self.normalModePullUp
            window.setFrame(frame, display: false)
            window.makeKey()
        }

        installDismissMonitors()
    }

    /// In non-fullscreen mode, shift the popover upward by this much into
    /// the dead space NSPopover reserves for the (hidden) anchor arrow,
    /// tuned so the visible top of the popover sits at the same y as a
    /// native NSMenu's first row.
    private static let normalModePullUp: CGFloat = 10

    private static func fullscreenBarInset() -> CGFloat {
        if let screen = NSScreen.main {
            let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
            if barHeight > 0 { return barHeight + 12 }
        }
        return 48
    }

    /// True if any normal-layer window currently fills the entire main
    /// screen — proxy for "some other app is in fullscreen".
    private static func isAnyAppFullscreen() -> Bool {
        guard
            let infoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
            let screen = NSScreen.main
        else { return false }

        let w = screen.frame.width
        let h = screen.frame.height

        for info in infoList {
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let bw = bounds["Width"] ?? 0
            let bh = bounds["Height"] ?? 0
            if bw >= w - 1 && bh >= h - 1 { return true }
        }
        return false
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
