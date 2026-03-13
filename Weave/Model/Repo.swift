import Foundation

@Observable
class Repo: Identifiable {
    let id = UUID()
    var name: String
    var path: String
    var threads: [WeaveThread] = []
    var isExpanded: Bool = true
    var defaultTabs: [String]

    init(path: String, defaultTabs: [String] = [""]) {
        self.path = path
        self.name = GitWorktree.repoName(path: path)
        self.defaultTabs = defaultTabs
    }
}
