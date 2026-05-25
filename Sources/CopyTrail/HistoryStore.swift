import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let ts: TimeInterval

    init(id: UUID = UUID(), text: String, ts: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.text = text
        self.ts = ts
    }

    var preview: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let limit = 80
        if trimmed.count > limit {
            return String(trimmed.prefix(limit)) + "…"
        }
        return trimmed
    }
}

final class HistoryStore: ObservableObject {
    static let maxEntryBytes = 1 << 20 // 1 MiB

    @Published private(set) var entries: [HistoryEntry] = []

    private let url: URL
    private var maxLen: Int
    private var persistWork: DispatchWorkItem?

    init(maxLen: Int) {
        self.url = (try? Paths.historyURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.maxLen = maxLen
        load()
    }

    /// Add `text` to the front of history. Returns true if history changed.
    /// Duplicates are moved to the front. Entries over 1 MiB are dropped.
    @discardableResult
    func add(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.utf8.count <= Self.maxEntryBytes else { return false }
        if let top = entries.first, top.text == text { return false }
        entries.removeAll { $0.text == text }
        entries.insert(HistoryEntry(text: text), at: 0)
        trim()
        schedulePersist()
        return true
    }

    func search(_ query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter { $0.text.lowercased().contains(q) }
    }

    func setMax(_ n: Int) {
        maxLen = n
        trim()
        schedulePersist()
    }

    private func trim() {
        if entries.count > maxLen {
            entries = Array(entries.prefix(maxLen))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = Array(decoded.prefix(maxLen))
        }
    }

    private func schedulePersist() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func persistNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Force-flush pending persistence; safe to call on shutdown.
    func flush() {
        persistWork?.cancel()
        persistNow()
    }
}
