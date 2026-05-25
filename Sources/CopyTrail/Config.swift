import Foundation

private struct ConfigPayload: Codable {
    var maxHistory: Int
    var maxImageMB: Int?
}

final class Config: ObservableObject {
    static let defaultMaxHistory = 100
    static let minMaxHistory = 10
    static let maxMaxHistory = 1000

    static let defaultMaxImageMB = 10
    static let minMaxImageMB = 0      // 0 disables image capture entirely
    static let maxMaxImageMB = 100

    @Published var maxHistory: Int
    @Published var maxImageMB: Int

    private let url: URL

    init() {
        self.url = (try? Paths.configURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.maxHistory = Self.defaultMaxHistory
        self.maxImageMB = Self.defaultMaxImageMB
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
        if payload.maxImageMB == nil {
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

    var maxImageBytes: Int { maxImageMB * 1024 * 1024 }

    private func clampHistory(_ n: Int) -> Int {
        max(Self.minMaxHistory, min(Self.maxMaxHistory, n))
    }

    private func clampImageMB(_ n: Int) -> Int {
        max(Self.minMaxImageMB, min(Self.maxMaxImageMB, n))
    }

    private func save() {
        let payload = ConfigPayload(maxHistory: maxHistory, maxImageMB: maxImageMB)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
