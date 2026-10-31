import AppKit
import SwiftUI

final class PreviewPanelController {
    private var panel: NSPanel?
    private let store: HistoryStore

    private let gap: CGFloat = 4
    /// Preferred width (Settings); narrowed when the screen has less room beside the menu.
    var panelWidth: CGFloat = CGFloat(Config.defaultPreviewWidth)
    private let padding: CGFloat = 10
    private let minHeight: CGFloat = 50

    init(store: HistoryStore) {
        self.store = store
    }

    /// Shows `entry` beside `menuWindow` (the open history menu's window).
    func show(entry: HistoryEntry, menuWindow: NSWindow) {
        let visibleScreenRect = menuWindow.frame
        let maxHeight = visibleScreenRect.height

        let width = fittedWidth(beside: visibleScreenRect, screen: menuWindow.screen)
        let contentHeight = measureContentHeight(for: entry, width: width)
        let panelHeight = min(max(contentHeight, minHeight), maxHeight)
        let panelSize = NSSize(width: width, height: panelHeight)

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
            screen: menuWindow.screen
        )
        panel.setFrameOrigin(origin)

        panel.alphaValue = 1
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func teardown() {
        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    // MARK: - Private

    /// The wider side of the menu decides how much room there is.
    private func fittedWidth(beside menuRect: NSRect, screen: NSScreen?) -> CGFloat {
        guard let screenFrame = (screen ?? NSScreen.main)?.visibleFrame else { return panelWidth }
        let room = max(menuRect.minX - screenFrame.minX, screenFrame.maxX - menuRect.maxX) - gap
        return max(min(panelWidth, room), CGFloat(Config.minPreviewWidth))
    }

    private func measureContentHeight(for entry: HistoryEntry, width panelWidth: CGFloat) -> CGFloat {
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
        p.level = .popUpMenu
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = p
    }

    private func calculateOrigin(
        panelSize: NSSize,
        visibleScreenRect: NSRect,
        screen: NSScreen?
    ) -> NSPoint {
        // Align top edges with the menu.
        let y = visibleScreenRect.maxY - panelSize.height

        // Default: left of the menu.
        var x = visibleScreenRect.minX - panelSize.width - gap

        // If not enough room on the left, flip to the right.
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        if let screenFrame = screen?.visibleFrame {
            if x < screenFrame.minX {
                x = visibleScreenRect.maxX + gap
            }
        }

        return NSPoint(x: x, y: y)
    }
}
