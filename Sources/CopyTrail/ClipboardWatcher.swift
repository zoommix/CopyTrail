import AppKit
import Foundation

final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let interval: TimeInterval
    private let onChange: (String) -> Void

    init(interval: TimeInterval = 0.3, onChange: @escaping (String) -> Void) {
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
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        onChange(text)
    }

    /// Write `text` to the clipboard. The watcher will observe the resulting
    /// change on the next tick and feed it back into the history store,
    /// which dedupes-to-front — so restoring an entry naturally moves it
    /// to the top of history.
    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
