import AppKit
import Combine
import CryptoKit
import Foundation

enum EntryKind: String, Codable {
    case text
    case image
}

/// Captures what the watcher saw on the clipboard.
enum ClipboardItem {
    case text(String)
    case image(pngData: Data)
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: EntryKind
    let ts: TimeInterval

    /// Set for `.text` entries.
    let text: String?

    /// Set for `.image` entries. Filename only — resolved against the
    /// images directory by HistoryStore.
    let imageFile: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageByteCount: Int?

    init(
        id: UUID = UUID(),
        kind: EntryKind,
        ts: TimeInterval = Date().timeIntervalSince1970,
        text: String? = nil,
        imageFile: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageByteCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.ts = ts
        self.text = text
        self.imageFile = imageFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageByteCount = imageByteCount
    }

    // Decoder that tolerates the older text-only history.json format:
    // missing `kind` ⇒ `.text`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ts = try c.decode(TimeInterval.self, forKey: .ts)
        kind = try c.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .text
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        imageWidth = try c.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try c.decodeIfPresent(Int.self, forKey: .imageHeight)
        imageByteCount = try c.decodeIfPresent(Int.self, forKey: .imageByteCount)
    }

    var preview: String {
        switch kind {
        case .text:
            let raw = text ?? ""
            let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            let limit = 80
            if trimmed.count > limit {
                return String(trimmed.prefix(limit)) + "…"
            }
            return trimmed
        case .image:
            let w = imageWidth ?? 0
            let h = imageHeight ?? 0
            let size = imageByteCount.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "?"
            return "Image  \(w)×\(h)  \(size)"
        }
    }
}

final class HistoryStore: ObservableObject {
    static let maxTextBytes = 1 << 20  // 1 MiB

    @Published private(set) var entries: [HistoryEntry] = []

    private let historyURL: URL
    let imagesDir: URL

    private var maxLen: Int
    private var maxImageBytes: Int
    private var persistWork: DispatchWorkItem?

    init(maxLen: Int, maxImageBytes: Int) {
        self.historyURL = (try? Paths.historyURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.imagesDir = (try? Paths.imagesURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.maxLen = maxLen
        self.maxImageBytes = maxImageBytes
        load()
        pruneOrphanImageFiles()
    }

    func setMaxImageBytes(_ n: Int) {
        maxImageBytes = n
    }

    // MARK: Read-side helpers

    func imageURL(for entry: HistoryEntry) -> URL? {
        guard let file = entry.imageFile else { return nil }
        return imagesDir.appendingPathComponent(file)
    }

    func search(_ query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter { entry in
            switch entry.kind {
            case .text:
                return (entry.text ?? "").lowercased().contains(q)
            case .image:
                return entry.preview.lowercased().contains(q)
            }
        }
    }

    // MARK: Mutation

    /// Add a clipboard item to history. Dedupes-to-front by text equality
    /// or image-hash. Returns true if anything changed.
    @discardableResult
    func add(_ item: ClipboardItem) -> Bool {
        switch item {
        case .text(let text):
            return addText(text)
        case .image(let data):
            return addImage(data)
        }
    }

    private func addText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.utf8.count <= Self.maxTextBytes else { return false }
        if let top = entries.first, top.kind == .text, top.text == text { return false }

        if let dupIdx = entries.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            let existing = entries.remove(at: dupIdx)
            entries.insert(existing, at: 0)
        } else {
            entries.insert(HistoryEntry(kind: .text, text: text), at: 0)
        }
        trim()
        schedulePersist()
        return true
    }

    private func addImage(_ pngData: Data) -> Bool {
        guard maxImageBytes > 0 else { return false }
        guard pngData.count <= maxImageBytes else { return false }
        let hash = Self.sha256Hex(pngData)
        let filename = hash + ".png"

        if let top = entries.first, top.kind == .image, top.imageFile == filename {
            return false
        }

        if let dupIdx = entries.firstIndex(where: { $0.kind == .image && $0.imageFile == filename }) {
            let existing = entries.remove(at: dupIdx)
            entries.insert(existing, at: 0)
            trim()
            schedulePersist()
            return true
        }

        guard let (w, h) = imageDimensions(pngData) else { return false }

        let url = imagesDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            return false
        }

        let entry = HistoryEntry(
            kind: .image,
            imageFile: filename,
            imageWidth: w,
            imageHeight: h,
            imageByteCount: pngData.count
        )
        entries.insert(entry, at: 0)
        trim()
        schedulePersist()
        return true
    }

    func setMax(_ n: Int) {
        maxLen = n
        trim()
        schedulePersist()
    }

    private func trim() {
        if entries.count > maxLen {
            let dropped = entries[maxLen...]
            entries = Array(entries.prefix(maxLen))
            for entry in dropped where entry.kind == .image {
                if let file = entry.imageFile {
                    try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
                }
            }
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
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
        try? data.write(to: historyURL, options: .atomic)
    }

    func flush() {
        persistWork?.cancel()
        persistNow()
    }

    /// Remove any files in the images directory that aren't referenced by
    /// the current entries list. Runs once at startup.
    private func pruneOrphanImageFiles() {
        let referenced = Set(entries.compactMap { $0.imageFile })
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: imagesDir.path) else { return }
        for file in contents where !referenced.contains(file) {
            try? fm.removeItem(at: imagesDir.appendingPathComponent(file))
        }
    }

    // MARK: Helpers

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func imageDimensions(_ data: Data) -> (Int, Int)? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return nil }
        return (w, h)
    }
}
