import Foundation

private struct ConfigPayload: Codable {
    var maxHistory: Int
    var maxImageMB: Int?
    var previewWidth: Int?
}

final class Config: ObservableObject {
    static let defaultMaxHistory = 100
    static let minMaxHistory = 10
    static let maxMaxHistory = 100_000

    static let defaultMaxImageMB = 10
    static let minMaxImageMB = 0      // 0 disables image capture entirely
    static let maxMaxImageMB = 100

    static let defaultPreviewWidth = 300
    static let minPreviewWidth = 200
    static let maxPreviewWidth = 1200

    @Published var maxHistory: Int
    @Published var maxImageMB: Int
    @Published var previewWidth: Int

    private let url: URL

    init() {
        self.url = (try? Paths.configURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.maxHistory = Self.defaultMaxHistory
        self.maxImageMB = Self.defaultMaxImageMB
        self.previewWidth = Self.defaultPreviewWidth
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ConfigPayload.self, from: data) else {
            save()
            return
        }
        maxHistory = clampHistory(payload.maxHistory)
        maxImageMB = clampImageMB(payload.maxImageMB ?? Self.defaultMaxImageMB)
        previewWidth = clampPreviewWidth(payload.previewWidth ?? Self.defaultPreviewWidth)
        if payload.maxImageMB == nil || payload.previewWidth == nil {
            save() // migrate old config files
        }
    }

    func setMaxHistory(_ n: Int) {
        maxHistory = clampHistory(n)
        save()
    }

    func setMaxImageMB(_ n: Int) {
        maxImageMB = clampImageMB(n)
        save()
    }

    func setPreviewWidth(_ n: Int) {
        previewWidth = clampPreviewWidth(n)
        save()
    }

    var maxImageBytes: Int { maxImageMB * 1024 * 1024 }

    private func clampHistory(_ n: Int) -> Int {
        max(Self.minMaxHistory, min(Self.maxMaxHistory, n))
    }

    private func clampImageMB(_ n: Int) -> Int {
        max(Self.minMaxImageMB, min(Self.maxMaxImageMB, n))
    }

    private func clampPreviewWidth(_ n: Int) -> Int {
        max(Self.minPreviewWidth, min(Self.maxPreviewWidth, n))
    }

    private func save() {
        let payload = ConfigPayload(maxHistory: maxHistory, maxImageMB: maxImageMB, previewWidth: previewWidth)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
