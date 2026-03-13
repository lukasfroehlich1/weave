import Foundation

struct CachedPR: Codable {
    var number: Int
    var url: String
    var state: String
}

struct PersistedState: Codable {
    var repos: [Repo] = []
    var activeThreadID: UUID?
    var settings = AppSettings()

    private static let defaultsKey = "AppState"

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return PersistedState() }
        return (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? PersistedState()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
