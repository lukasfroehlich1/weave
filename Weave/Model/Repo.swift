import Foundation

@MainActor
@Observable
class Repo: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: String
    var threads: [WeaveThread] = []
    var isExpanded: Bool = true
    var defaultTabs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, path, threads, isExpanded, defaultTabs
    }

    init(path: String, defaultTabs: [String] = [""]) {
        self.id = UUID()
        self.path = path
        self.name = GitWorktree.repoName(path: path)
        self.defaultTabs = defaultTabs
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        threads = try c.decodeIfPresent([WeaveThread].self, forKey: .threads) ?? []
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        defaultTabs = try c.decodeIfPresent([String].self, forKey: .defaultTabs) ?? [""]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(path, forKey: .path)
        try c.encode(threads, forKey: .threads)
        try c.encode(isExpanded, forKey: .isExpanded)
        try c.encode(defaultTabs, forKey: .defaultTabs)
    }

    func refreshThreads() async throws {
        let repoPath = path
        let repoName = GitWorktree.repoName(path: repoPath)
        let base = "\(AppSettings.shared.resolvedWorktreeBase)/\(repoName)/"
        let branchPrefix = AppSettings.shared.branchPrefix

        let worktrees = try await Task.detached {
            try GitWorktree.list(repoPath: repoPath)
        }.value

        let existingByPath = Dictionary(uniqueKeysWithValues: threads.map { ($0.worktreePath, $0) })

        var refreshed: [WeaveThread] = []
        for wt in worktrees {
            if wt.bare { continue }

            let isMain = wt.path == repoPath
            if !isMain, !wt.path.hasPrefix(base) { continue }

            if let existing = existingByPath[wt.path] {
                existing.isMainWorktree = isMain
                refreshed.append(existing)
            } else {
                let title = isMain ? wt.branch : WeaveHelpers.titleFromBranch(wt.branch, prefix: branchPrefix)
                let thread = WeaveThread(name: title, worktreePath: wt.path, branch: wt.branch, isMainWorktree: isMain)
                refreshed.append(thread)
            }
        }

        refreshed.sort { lhs, _ in lhs.isMainWorktree }
        threads = refreshed
    }

    func createThread(
        name: String,
        onClose: @escaping @MainActor (WeaveThread, Tab) -> Void
    ) async throws -> WeaveThread {
        let title = name.trimmingCharacters(in: .whitespaces)
        let repoPath = path
        let repoName = GitWorktree.repoName(path: repoPath)
        let resolvedBase = AppSettings.shared.resolvedWorktreeBase
        let branchPrefix = AppSettings.shared.branchPrefix
        let baseBranch = AppSettings.shared.baseBranch
        let defaultTabs = self.defaultTabs

        let branch = WeaveHelpers.sanitizeBranch(title, prefix: branchPrefix)

        guard !threads.contains(where: { $0.branch == branch }) else {
            throw RepoError.threadExists(title)
        }

        let wtPath = "\(resolvedBase)/\(repoName)/\(branch)"
        let parentDir = URL(fileURLWithPath: wtPath).deletingLastPathComponent().path

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            let startPoint: String? = if let explicit = baseBranch {
                explicit
            } else if let detected = GitWorktree.defaultRemoteBranch(repoPath: repoPath) {
                detected + "^{commit}"
            } else if GitWorktree.hasCommits(repoPath: repoPath) {
                "HEAD"
            } else {
                nil
            }
            try GitWorktree.add(repoPath: repoPath, path: wtPath, branch: branch, startPoint: startPoint)
        }.value

        let thread = WeaveThread(name: title, worktreePath: wtPath, branch: branch)
        threads.append(thread)

        for (i, cmd) in defaultTabs.enumerated() {
            let tab = thread.addTab(onClose: { [weak thread] tab in
                guard let thread else { return }
                onClose(thread, tab)
            })
            if !cmd.isEmpty, let pane = tab.activePane {
                Task { @MainActor [weak pane] in
                    try? await Task.sleep(for: .milliseconds(500 + i * 200))
                    pane?.send(text: cmd + "\n")
                }
            }
        }

        thread.tabs.first?.panes.first?.agentStatus = .review
        return thread
    }

    enum RepoError: LocalizedError {
        case threadExists(String)

        var errorDescription: String? {
            switch self {
            case let .threadExists(name): "Thread '\(name)' already exists"
            }
        }
    }

    func deleteThread(_ thread: WeaveThread) async throws {
        let repoPath = path
        let wtPath = thread.worktreePath
        let branch = thread.branch
        let force = AppSettings.shared.forceRemoveWorktree
        let deleteBranch = AppSettings.shared.deleteBranchOnRemove

        try await Task.detached(priority: .userInitiated) {
            try GitWorktree.remove(repoPath: repoPath, path: wtPath, force: force)
            if deleteBranch {
                try? GitWorktree.deleteBranch(repoPath: repoPath, branch: branch)
            }
        }.value

        threads.removeAll { $0.id == thread.id }
    }

    func removeAllSurfaces() {
        for thread in threads {
            thread.removeAllSurfaces()
        }
    }
}
