import AppKit
import SwiftUI

final class PreviewPanelController {
    private var panel: NSPanel?
    private let store: HistoryStore

    private let gap: CGFloat = 4
    private let panelWidth: CGFloat = 300
    private let padding: CGFloat = 10
    private let minHeight: CGFloat = 50

    init(store: HistoryStore) {
        self.store = store
    }

    func show(entry: HistoryEntry, rowIndex: Int, popoverWindow: NSWindow) {
        guard let popContentView = popoverWindow.contentView else { return }
        let visibleRect = popContentView.convert(popContentView.bounds, to: nil)
        let visibleScreenRect = popoverWindow.convertToScreen(visibleRect)
        let maxHeight = visibleScreenRect.height

        let contentHeight = measureContentHeight(for: entry)
        let panelHeight = min(max(contentHeight, minHeight), maxHeight)
        let panelSize = NSSize(width: panelWidth, height: panelHeight)

        let contentView = PreviewContentView(entry: entry, store: store)
        let hostingView = NSHostingView(rootView: contentView)

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        panel.setContentSize(panelSize)

        let origin = calculateOrigin(
            panelSize: panelSize,
            visibleScreenRect: visibleScreenRect,
            popoverWindow: popoverWindow
        )
        panel.setFrameOrigin(origin)

        if panel.parent != popoverWindow {
            panel.parent?.removeChildWindow(panel)
            popoverWindow.addChildWindow(panel, ordered: .above)
        }

        panel.alphaValue = 1
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    func teardown() {
        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        panel.contentView = nil
        self.panel = nil
    }

    // MARK: - Private

    private func measureContentHeight(for entry: HistoryEntry) -> CGFloat {
        let insetWidth = panelWidth - padding * 2

        switch entry.kind {
        case .text:
            let text = entry.text ?? ""
            let font = NSFont.systemFont(ofSize: 13)
            let boundingRect = (text as NSString).boundingRect(
                with: NSSize(width: insetWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            return ceil(boundingRect.height) + padding * 2

        case .image:
            let imgPadding: CGFloat = 8
            let availableWidth = panelWidth - imgPadding * 2
            let w = CGFloat(entry.imageWidth ?? 0)
            let h = CGFloat(entry.imageHeight ?? 0)
            guard w > 0, h > 0 else { return minHeight }
            let scale = min(availableWidth / w, 1.0)
            return ceil(h * scale) + imgPadding * 2
        }
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = p
    }

    private func calculateOrigin(
        panelSize: NSSize,
        visibleScreenRect: NSRect,
        popoverWindow: NSWindow
    ) -> NSPoint {
        // Align top edges using the visible content rect.
        let y = visibleScreenRect.maxY - panelSize.height

        // Default: left of the visible popover.
        var x = visibleScreenRect.minX - panelSize.width - gap

        // If not enough room on the left, flip to the right.
        let screen = popoverWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let screenFrame = screen?.visibleFrame {
            if x < screenFrame.minX {
                x = visibleScreenRect.maxX + gap
            }
        }

        return NSPoint(x: x, y: y)
    }
}
