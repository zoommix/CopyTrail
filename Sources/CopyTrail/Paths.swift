import Foundation

enum Paths {
    static let appDirName = "CopyTrail"

    static func appSupportDir() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appDirName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func configURL() throws -> URL {
        try appSupportDir().appendingPathComponent("config.json")
    }

    static func historyURL() throws -> URL {
        try appSupportDir().appendingPathComponent("history.json")
    }
}
