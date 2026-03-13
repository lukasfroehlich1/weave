import Foundation

struct WeaveConfig: Codable, Sendable {
    var worktreeBase: String?
    var repos: [RepoConfig]?
    var editor: String?
    var branchPrefix: String?
    var deleteBranchOnRemove: Bool?
    var forceRemoveWorktree: Bool?

    struct RepoConfig: Codable, Sendable {
        var path: String
        var defaultTabs: [String]?
    }

    var resolvedWorktreeBase: String {
        let base = worktreeBase ?? "~/.weave/worktrees"
        return base.expandingTilde
    }

    static let configDir = "~/.config/weave".expandingTilde
    static let configPath = "~/.config/weave/config.json".expandingTilde

    static func load() -> WeaveConfig {
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return WeaveConfig()
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(WeaveConfig.self, from: data)) ?? WeaveConfig()
    }

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        fm.createFile(atPath: Self.configPath, contents: data)
    }

    mutating func addRepo(path: String, defaultTabs: [String]? = nil) {
        let expanded = path.expandingTilde
        if repos == nil { repos = [] }
        guard !repos!.contains(where: { $0.path.expandingTilde == expanded }) else { return }
        repos!.append(RepoConfig(path: path, defaultTabs: defaultTabs))
    }

    mutating func removeRepo(path: String) {
        let expanded = path.expandingTilde
        repos?.removeAll { $0.path.expandingTilde == expanded }
    }
}
