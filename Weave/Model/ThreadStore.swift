import Foundation
import AppKit

@MainActor
@Observable
class ThreadStore {
    var repos: [Repo] = []
    var activeThreadID: UUID?
    var isCreatingThread = false
    var creatingThreadRepoID: UUID?
    var error: String?
    var threadToDelete: WeaveThread?
    var config = WeaveConfig()
    var pendingCreation: (name: String, repoID: UUID)?
    var deletingThreadIDs: Set<UUID> = []
    private let statusMonitor = AgentStatusMonitor()
    private var autoSaveTask: Task<Void, Never>?
    private var prPollTask: Task<Void, Never>?

    var activeThread: WeaveThread? {
        for repo in repos {
            if let thread = repo.threads.first(where: { $0.id == activeThreadID }) {
                return thread
            }
        }
        return nil
    }

    var activeRepo: Repo? {
        for repo in repos {
            if repo.threads.contains(where: { $0.id == activeThreadID }) {
                return repo
            }
        }
        return repos.first
    }

    func repo(for thread: WeaveThread) -> Repo? {
        repos.first { $0.threads.contains { $0.id == thread.id } }
    }

    // MARK: - Startup

    private var threadTitles: [String: String] = [:]
    private var cachedPRs: [String: CachedPR] = [:]
    private var threadTimestamps: [String: Date] = [:]

    func loadConfig() async {
        config = WeaveConfig.load()

        HookSetup.install()
        statusMonitor.onStatusChange = { [weak self] tabIDString, status in
            guard let self else { return }
            for repo in repos {
                for thread in repo.threads {
                    if let tab = thread.tabs.first(where: { $0.id.uuidString == tabIDString }) {
                        if status == .idle && (tab.agentStatus == .working || tab.agentStatus == .needsInput) {
                            tab.agentStatus = thread.id == activeThreadID ? .idle : .review
                        } else {
                            tab.agentStatus = status
                        }
                        return
                    }
                }
            }
        }
        statusMonitor.start()

        let state = AppState.load()
        threadTitles = state.threadTitles ?? [:]
        savedSessions = state.threadSessions ?? [:]
        cachedPRs = state.threadPRs ?? [:]
        threadTimestamps = state.threadTimestamps ?? [:]

        for repoConfig in config.repos ?? [] {
            let path = repoConfig.path.expandingTilde
            guard !repos.contains(where: { $0.path == path }) else { continue }

            let isRepo = await Task.detached { GitWorktree.isGitRepo(path: path) }.value
            guard isRepo else { continue }

            let repo = Repo(path: path, defaultTabs: repoConfig.defaultTabs ?? [""])
            repos.append(repo)
        }

        for repo in repos {
            await refreshThreads(for: repo)
        }

        for repo in repos {
            for thread in repo.threads {
                if let cached = cachedPRs[thread.branch],
                   let url = URL(string: cached.url),
                   let state = PRState(rawValue: cached.state) {
                    thread.prInfo = PRInfo(number: cached.number, url: url, state: state)
                }
            }
        }

        if let repoPath = state.activeRepoPath,
           let threadBranch = state.activeThreadName,
           let repo = repos.first(where: { $0.path == repoPath }),
           let thread = repo.threads.first(where: { $0.branch == threadBranch }) {
            switchTo(thread)
        }

        startAutoSave()
        startPRPolling()
    }

    private func startAutoSave() {
        autoSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { break }
                self.saveScrollback()
            }
        }
    }

    private func startPRPolling() {
        prPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refreshPRs()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refreshPRs() async {
        for repo in repos {
            let repoPath = repo.path
            for thread in repo.threads {
                let branch = thread.branch
                let newPR = await Task.detached {
                    PRMonitor.fetchPR(repoPath: repoPath, branch: branch)
                }.value
                if thread.prInfo != newPR {
                    thread.prInfo = newPR
                }
            }
        }
        saveState()
    }

    private func buildPRCache() -> [String: CachedPR] {
        var cache: [String: CachedPR] = [:]
        for repo in repos {
            for thread in repo.threads {
                if let pr = thread.prInfo {
                    cache[thread.branch] = CachedPR(
                        number: pr.number,
                        url: pr.url.absoluteString,
                        state: pr.state.rawValue
                    )
                }
            }
        }
        return cache
    }

    private func buildTimestampCache() -> [String: Date] {
        var cache: [String: Date] = [:]
        for repo in repos {
            for thread in repo.threads {
                cache[thread.branch] = thread.lastActiveAt
            }
        }
        return cache
    }

    func saveState() {
        var state = AppState()
        if let thread = activeThread, let repo = repo(for: thread) {
            state.activeRepoPath = repo.path
            state.activeThreadName = thread.branch
        }
        state.threadTitles = threadTitles
        state.threadSessions = buildSessionSnapshots()
        state.threadPRs = buildPRCache()
        state.threadTimestamps = buildTimestampCache()
        state.save()
    }

    func saveScrollback() {
        for repo in repos {
            for thread in repo.threads {
                for (i, tab) in thread.tabs.enumerated() {
                    if let scrollback = tab.surfaceView?.readScrollback() {
                        SessionStore.saveScrollback(scrollback, branch: thread.branch, tabIndex: i)
                    }
                }
            }
        }
        saveState()
    }

    private func buildSessionSnapshots() -> [String: ThreadSession] {
        var sessions = savedSessions
        for repo in repos {
            for thread in repo.threads where !thread.tabs.isEmpty {
                let tabSnapshots = thread.tabs.map { TabSnapshot(title: $0.title) }
                let activeIdx = thread.tabs.firstIndex { $0.id == thread.activeTabID }
                sessions[thread.branch] = ThreadSession(
                    branch: thread.branch,
                    tabs: tabSnapshots,
                    activeTabIndex: activeIdx
                )
            }
        }
        return sessions
    }

    // MARK: - Repo management

    func addRepo(path: String) async {
        let expanded = path.expandingTilde
        guard !repos.contains(where: { $0.path == expanded }) else {
            error = "Repository already added"
            return
        }

        let isRepo = await Task.detached { GitWorktree.isGitRepo(path: expanded) }.value
        guard isRepo else {
            error = "Not a git repository: \(path)"
            return
        }

        let repo = Repo(path: expanded)
        repos.append(repo)
        await refreshThreads(for: repo)

        config.addRepo(path: expanded)
        config.save()
    }

    func removeRepo(_ repo: Repo) {
        for thread in repo.threads {
            for tab in thread.tabs {
                tab.surfaceView?.removeFromSuperview()
                tab.surfaceView = nil
            }
        }

        repos.removeAll { $0.id == repo.id }

        if activeThread == nil {
            activeThreadID = repos.first?.threads.first?.id
        }

        config.removeRepo(path: repo.path)
        config.save()
        saveState()
    }

    // MARK: - Thread management

    func refreshThreads(for repo: Repo) async {
        let repoPath = repo.path
        let repoName = GitWorktree.repoName(path: repoPath)
        let base = "\(config.resolvedWorktreeBase)/\(repoName)/"

        do {
            let worktrees = try await Task.detached {
                try GitWorktree.list(repoPath: repoPath)
            }.value

            let existingByPath = Dictionary(uniqueKeysWithValues: repo.threads.map { ($0.worktreePath, $0) })

            var refreshed: [WeaveThread] = []
            for wt in worktrees {
                if wt.bare || wt.path == repoPath { continue }
                if !wt.path.hasPrefix(base) { continue }

                if let existing = existingByPath[wt.path] {
                    refreshed.append(existing)
                } else {
                    let title = threadTitles[wt.branch] ?? Self.titleFromBranch(wt.branch, prefix: config.branchPrefix ?? "")
                    let thread = WeaveThread(name: title, worktreePath: wt.path, branch: wt.branch)
                    if let saved = threadTimestamps[wt.branch] {
                        thread.lastActiveAt = saved
                    }
                    refreshed.append(thread)
                }
            }

            repo.threads = refreshed
        } catch {
            self.error = "Failed to list worktrees: \(error.localizedDescription)"
        }
    }

    func createThread(name: String, in repo: Repo) async {
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let branch = Self.sanitizeBranch(title, prefix: config.branchPrefix ?? "")
        guard !repo.threads.contains(where: { $0.branch == branch }) else {
            error = "Thread '\(title)' already exists"
            return
        }

        pendingCreation = (name: title, repoID: repo.id)
        defer { pendingCreation = nil }

        let repoPath = repo.path
        let repoName = GitWorktree.repoName(path: repoPath)
        let wtPath = "\(config.resolvedWorktreeBase)/\(repoName)/\(branch)"
        let parentDir = URL(fileURLWithPath: wtPath).deletingLastPathComponent().path

        do {
            try await Task.detached {
                let fm = FileManager.default
                if !fm.fileExists(atPath: parentDir) {
                    try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                }
                try GitWorktree.add(repoPath: repoPath, path: wtPath, branch: branch)
            }.value
        } catch {
            self.error = "Failed to create thread: \(error.localizedDescription)"
            try? await Task.detached {
                try? GitWorktree.remove(repoPath: repoPath, path: wtPath, force: true)
            }.value
            return
        }

        threadTitles[branch] = title
        let thread = WeaveThread(name: title, worktreePath: wtPath, branch: branch)
        repo.threads.append(thread)
        activeThreadID = thread.id

        let tabCommands = repo.defaultTabs
        for (i, cmd) in tabCommands.enumerated() {
            let tab = addTab(to: thread)
            if !cmd.isEmpty {
                let command = cmd
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.2) {
                    if let surface = tab.surfaceView?.surface {
                        let text = command + "\n"
                        text.withCString { ptr in
                            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
                        }
                    }
                }
            }
        }

        saveState()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusActiveSurface()
        }
    }

    func deleteThread(_ thread: WeaveThread) async {
        guard let repo = repo(for: thread) else { return }

        deletingThreadIDs.insert(thread.id)
        defer { deletingThreadIDs.remove(thread.id) }

        for tab in thread.tabs {
            AgentStatusMonitor.removeStatus(tabID: tab.id.uuidString)
            tab.surfaceView?.removeFromSuperview()
            tab.surfaceView = nil
        }
        thread.tabs.removeAll()

        let force = config.forceRemoveWorktree ?? true
        let repoPath = repo.path
        let wtPath = thread.worktreePath
        let branch = thread.branch
        let deleteBranch = config.deleteBranchOnRemove ?? true

        do {
            try await Task.detached {
                try GitWorktree.remove(repoPath: repoPath, path: wtPath, force: force)
                if deleteBranch {
                    try? GitWorktree.deleteBranch(repoPath: repoPath, branch: branch)
                }
            }.value
        } catch {
            self.error = "Failed to remove worktree: \(error.localizedDescription)"
        }

        threadTitles.removeValue(forKey: thread.branch)
        SessionStore.removeScrollback(branch: thread.branch)
        repo.threads.removeAll { $0.id == thread.id }

        if activeThreadID == thread.id {
            activeThreadID = repo.threads.first?.id ?? repos.flatMap(\.threads).first?.id
            if let next = activeThread {
                ensureTab(for: next)
            }
        }

        saveState()
    }

    func switchTo(_ thread: WeaveThread) {
        activeThreadID = thread.id
        for tab in thread.tabs where tab.agentStatus == .review {
            tab.agentStatus = .idle
        }
        ensureTab(for: thread)
        focusActiveSurface()
        saveState()
    }

    // MARK: - Tab management

    @discardableResult
    func addTab(to thread: WeaveThread) -> TerminalTab {
        let tab = TerminalTab()
        let surface = createSurface(workingDirectory: thread.worktreePath, tabID: tab.id)

        surface.onTitleChange = { [weak tab] title in
            tab?.title = title
        }
        surface.onClose = { [weak self, weak thread, weak tab] in
            guard let self, let thread, let tab else { return }
            self.closeTab(tab, in: thread)
        }
        surface.onInput = { [weak thread] in
            thread?.lastActiveAt = Date()
        }

        tab.surfaceView = surface
        thread.tabs.append(tab)
        thread.activeTabID = tab.id
        focusActiveSurface()
        return tab
    }

    func closeTab(_ tab: TerminalTab, in thread: WeaveThread) {
        if let scrollback = tab.surfaceView?.readScrollback(),
           let idx = thread.tabs.firstIndex(where: { $0.id == tab.id }) {
            SessionStore.saveScrollback(scrollback, branch: thread.branch, tabIndex: idx)
        }
        saveState()

        AgentStatusMonitor.removeStatus(tabID: tab.id.uuidString)
        tab.surfaceView?.removeFromSuperview()
        tab.surfaceView = nil
        thread.tabs.removeAll { $0.id == tab.id }

        if thread.activeTabID == tab.id {
            thread.activeTabID = thread.tabs.last?.id
        }

        if !thread.tabs.isEmpty {
            focusActiveSurface()
        }
    }

    func openInEditor(_ thread: WeaveThread) {
        let editor = EditorLauncher.editor(forID: config.editor) ?? EditorLauncher.defaultEditor
        editor?.open(path: thread.worktreePath)
    }

    func setEditor(_ editor: Editor) {
        config.editor = editor.id
        config.save()
    }

    func selectNextTab() {
        guard let thread = activeThread, thread.tabs.count > 1 else { return }
        guard let idx = thread.tabs.firstIndex(where: { $0.id == thread.activeTabID }) else { return }
        let next = (idx + 1) % thread.tabs.count
        thread.activeTabID = thread.tabs[next].id
        focusActiveSurface()
    }

    private var allThreads: [WeaveThread] {
        repos.flatMap(\.threads)
    }

    func selectNextThread() {
        let threads = allThreads
        guard !threads.isEmpty else { return }
        guard let idx = threads.firstIndex(where: { $0.id == activeThreadID }) else {
            if let first = threads.first { switchTo(first) }
            return
        }
        let next = (idx + 1) % threads.count
        switchTo(threads[next])
    }

    func selectPreviousThread() {
        let threads = allThreads
        guard !threads.isEmpty else { return }
        guard let idx = threads.firstIndex(where: { $0.id == activeThreadID }) else {
            if let last = threads.last { switchTo(last) }
            return
        }
        let prev = (idx - 1 + threads.count) % threads.count
        switchTo(threads[prev])
    }

    func selectNextActiveThread() {
        let threads = allThreads
        guard let currentIdx = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        let count = threads.count
        for offset in 1..<count {
            let thread = threads[(currentIdx + offset) % count]
            if thread.agentStatus != .idle {
                switchTo(thread)
                return
            }
        }
    }

    func selectPreviousActiveThread() {
        let threads = allThreads
        guard let currentIdx = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        let count = threads.count
        for offset in 1..<count {
            let thread = threads[(currentIdx - offset + count) % count]
            if thread.agentStatus != .idle {
                switchTo(thread)
                return
            }
        }
    }

    func selectPreviousTab() {
        guard let thread = activeThread, thread.tabs.count > 1 else { return }
        guard let idx = thread.tabs.firstIndex(where: { $0.id == thread.activeTabID }) else { return }
        let prev = (idx - 1 + thread.tabs.count) % thread.tabs.count
        thread.activeTabID = thread.tabs[prev].id
        focusActiveSurface()
    }

    // MARK: - Private

    private var savedSessions: [String: ThreadSession] = [:]

    func restoreTabs(for thread: WeaveThread) {
        guard let session = savedSessions[thread.branch], !session.tabs.isEmpty else {
            addTab(to: thread)
            return
        }

        for (i, snapshot) in session.tabs.enumerated() {
            let tab = TerminalTab()
            tab.title = snapshot.title

            let scrollbackPath = SessionStore.scrollbackPath(branch: thread.branch, tabIndex: i)
            let command: String? = if FileManager.default.fileExists(atPath: scrollbackPath) {
                SessionStore.replayCommand(scrollbackPath: scrollbackPath)
            } else {
                nil
            }

            let surface = createSurface(workingDirectory: thread.worktreePath, command: command, tabID: tab.id)
            surface.onTitleChange = { [weak tab] title in tab?.title = title }
            surface.onClose = { [weak self, weak thread, weak tab] in
                guard let self, let thread, let tab else { return }
                self.closeTab(tab, in: thread)
            }
            surface.onInput = { [weak thread] in
                thread?.lastActiveAt = Date()
            }
            tab.surfaceView = surface
            thread.tabs.append(tab)
        }

        if let idx = session.activeTabIndex, idx < thread.tabs.count {
            thread.activeTabID = thread.tabs[idx].id
        } else {
            thread.activeTabID = thread.tabs.first?.id
        }
    }

    private func ensureTab(for thread: WeaveThread) {
        if thread.tabs.isEmpty {
            restoreTabs(for: thread)
        } else if thread.activeTab?.surfaceView == nil {
            if let tab = thread.activeTab {
                let surface = createSurface(workingDirectory: thread.worktreePath, tabID: tab.id)
                surface.onTitleChange = { [weak tab] title in
                    tab?.title = title
                }
                surface.onClose = { [weak self, weak thread, weak tab] in
                    guard let self, let thread, let tab else { return }
                    self.closeTab(tab, in: thread)
                }
                surface.onInput = { [weak thread] in
                    thread?.lastActiveAt = Date()
                }
                tab.surfaceView = surface
            }
        }
    }

    func focusActiveSurface() {
        guard let thread = activeThread, let tab = thread.activeTab, let surface = tab.surfaceView else { return }
        DispatchQueue.main.async {
            surface.window?.makeFirstResponder(surface)
        }
    }

    private func createSurface(workingDirectory: String, command: String? = nil, tabID: UUID? = nil) -> GhosttySurfaceView {
        var envVars: [String: String] = [:]
        if let tabID {
            envVars["WEAVE_TAB_ID"] = tabID.uuidString
        }
        return GhosttySurfaceView(workingDirectory: workingDirectory, command: command, envVars: envVars)
    }

    static func sanitizeBranch(_ title: String, prefix: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
            .map { String($0) }.joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return prefix + slug
    }


    static func titleFromBranch(_ branch: String, prefix: String) -> String {
        var name = branch
        if !prefix.isEmpty && name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}
