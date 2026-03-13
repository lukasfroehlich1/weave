import Foundation

struct CachedPR: Codable, Sendable {
    var number: Int
    var url: String
    var state: String
}

struct AppState: Codable, Sendable {
    var activeRepoPath: String?
    var activeThreadName: String?
    var threadTitles: [String: String]?
    var threadSessions: [String: ThreadSession]?
    var threadPRs: [String: CachedPR]?
    var threadTimestamps: [String: Date]?

    static let stateDir = "~/.weave".expandingTilde
    static let statePath = "~/.weave/state.json".expandingTilde

    static func load() -> AppState {
        guard let data = FileManager.default.contents(atPath: statePath) else {
            return AppState()
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(AppState.self, from: data)) ?? AppState()
    }

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.stateDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(self) else { return }
        fm.createFile(atPath: Self.statePath, contents: data)
    }
}
