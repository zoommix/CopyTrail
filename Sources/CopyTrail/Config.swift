import Foundation

struct ConfigPayload: Codable {
    var maxHistory: Int
}

final class Config: ObservableObject {
    static let defaultMaxHistory = 100
    static let minMaxHistory = 10
    static let maxMaxHistory = 1000

    @Published var maxHistory: Int

    private let url: URL

    init() {
        self.url = (try? Paths.configURL()) ?? URL(fileURLWithPath: "/dev/null")
        self.maxHistory = Self.defaultMaxHistory
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ConfigPayload.self, from: data) else {
            save()
            return
        }
        maxHistory = clamp(payload.maxHistory)
    }

    func setMaxHistory(_ n: Int) {
        maxHistory = clamp(n)
        save()
    }

    private func clamp(_ n: Int) -> Int {
        max(Self.minMaxHistory, min(Self.maxMaxHistory, n))
    }

    private func save() {
        let payload = ConfigPayload(maxHistory: maxHistory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
