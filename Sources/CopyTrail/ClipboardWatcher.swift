import AppKit
import Foundation

final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let interval: TimeInterval
    private let onChange: (ClipboardItem) -> Void

    init(interval: TimeInterval = 0.3, onChange: @escaping (ClipboardItem) -> Void) {
        self.interval = interval
        self.onChange = onChange
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let cc = pasteboard.changeCount
        guard cc != lastChangeCount else { return }
        lastChangeCount = cc
        guard let item = readClipboard() else { return }
        onChange(item)
    }

    private func readClipboard() -> ClipboardItem? {
        // Image takes priority — apps that copy images often also put a
        // text representation on the pasteboard, but the image is the
        // richer payload the user probably cares about.
        if let pngData = pasteboard.data(forType: .png) {
            return .image(pngData: pngData)
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let pngData = Self.pngFromTIFF(tiffData) {
            return .image(pngData: pngData)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    /// Write a text entry to the clipboard. The watcher will see the
    /// change on the next tick and feed it back into the store, which
    /// dedupes-to-front.
    func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Write an image (PNG) to the clipboard.
    func writeImage(pngData: Data) {
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    private static func pngFromTIFF(_ tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
