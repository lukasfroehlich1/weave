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
    var threadOrder: [String: [String]]?

    private static let defaultsKey = "AppState"

    static func load() -> AppState {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return AppState()
        }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
