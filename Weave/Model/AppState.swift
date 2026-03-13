import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
class AppState {
    var persisted = PersistedState()

    var activeThreadID: UUID? {
        get { persisted.activeThreadID }
        set { persisted.activeThreadID = newValue }
    }

    var isCreatingThread = false
    var creatingThreadRepoID: UUID?
    var showRepoPicker = false
    var isSidebarCollapsed = false
    var error: String?
    var threadToDelete: WeaveThread?
    var pendingCreation: (name: String, repoID: UUID)?
    var deletingThreadIDs: Set<UUID> = []
    var search = SearchState()
    private var hasLoaded = false
    private let statusMonitor = AgentStatusMonitor()
    private var prPollTask: Task<Void, Never>?

    var repos: [Repo] {
        get { persisted.repos }
        set { persisted.repos = newValue }
    }

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

    func loadConfig() async {
        persisted = PersistedState.load()
        AppSettings.shared = persisted.settings

        HookSetup.install()
        statusMonitor.onStatusChange = { [weak self] paneIDString, status in
            guard let self else { return }
            guard let (pane, thread) = self.findPane(id: paneIDString) else { return }
            if status == .idle {
                if pane.agentStatus == .working || pane.agentStatus == .needsInput {
                    pane.agentStatus = thread.id == activeThreadID ? .idle : .review
                }
                AgentStatusMonitor.removeStatus(tabID: paneIDString)
            } else {
                pane.agentStatus = status
            }
        }
        statusMonitor.start()

        for repo in repos {
            do {
                try await repo.refreshThreads()
            } catch {
                self.error = "Failed to list worktrees: \(error.localizedDescription)"
            }
        }

        for repo in repos {
            for thread in repo.threads {
                thread.restorePRFromCache()
            }
        }

        if let savedID = persisted.activeThreadID,
           let thread = repos.flatMap(\.threads).first(where: { $0.id == savedID })
        {
            switchTo(thread)
        }

        hasLoaded = true
        startPRPolling()
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
            for thread in repo.threads {
                await thread.refreshPR(repoPath: repo.path)
            }
        }
        saveState()
    }

    func saveState() {
        guard hasLoaded else { return }
        persisted.settings = AppSettings.shared
        persisted.save()
    }

    func saveScrollback() {
        for repo in repos {
            for thread in repo.threads {
                for tab in thread.tabs {
                    for pane in tab.panes {
                        pane.saveScrollback()
                    }
                }
            }
        }
        saveState()
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
        do {
            try await repo.refreshThreads()
        } catch {
            self.error = "Failed to list worktrees: \(error.localizedDescription)"
        }

        saveState()
    }

    func removeRepo(_ repo: Repo) {
        repo.removeAllSurfaces()
        repos.removeAll { $0.id == repo.id }

        if activeThread == nil {
            activeThreadID = repos.first?.threads.first?.id
        }

        saveState()
    }

    // MARK: - Thread management

    func createThread(name: String, in repo: Repo) async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        pendingCreation = (name: name, repoID: repo.id)
        defer { pendingCreation = nil }

        do {
            _ = try await repo.createThread(
                name: name,
                onClose: { [weak self] thread, tab in
                    self?.closeTab(tab, in: thread)
                }
            )
        } catch {
            self.error = error.localizedDescription
        }

        saveState()
    }

    func deleteThread(_ thread: WeaveThread) async {
        guard !thread.isMainWorktree else { return }
        guard let repo = repo(for: thread) else { return }

        deletingThreadIDs.insert(thread.id)
        defer { deletingThreadIDs.remove(thread.id) }

        thread.removeAllSurfaces()

        do {
            try await repo.deleteThread(thread)
        } catch {
            self.error = "Failed to remove worktree: \(error.localizedDescription)"
        }

        if activeThreadID == thread.id {
            activeThreadID = repo.threads.first?.id ?? repos.flatMap(\.threads).first?.id
            if let next = activeThread {
                ensureSurfaces(for: next)
            }
        }

        saveState()
    }

    func switchTo(_ thread: WeaveThread) {
        dismissSearch()
        activeThreadID = thread.id
        thread.clearReviewStatus()
        ensureSurfaces(for: thread)
        focusActiveSurface()
        saveState()
    }

    // MARK: - Tab management

    @discardableResult
    func addTab(to thread: WeaveThread) -> Tab {
        let tab = thread.addTab(onClose: { [weak self, weak thread] tab in
            guard let self, let thread else { return }
            self.closeTab(tab, in: thread)
        })
        focusActiveSurface()
        return tab
    }

    func closeTab(_ tab: Tab, in thread: WeaveThread) {
        thread.closeTab(tab)
        saveState()

        if !thread.tabs.isEmpty {
            focusActiveSurface()
        }
    }

    func renameThread(_ thread: WeaveThread, to name: String) {
        thread.name = name
        saveState()
    }

    func openInEditor(_ thread: WeaveThread) {
        let editor = EditorLauncher.editor(forID: AppSettings.shared.defaultEditor) ?? EditorLauncher.defaultEditor
        editor?.open(path: thread.worktreePath)
    }

    func setEditor(_ editor: Editor) {
        AppSettings.shared.defaultEditor = editor.id
        saveState()
    }

    func selectTab(at index: Int) {
        withTab { $0.selectTab(at: index) }
    }

    func selectLastTab() {
        withTab { $0.selectLastTab() }
    }

    func selectNextTab() {
        withTab { $0.selectNextTab() }
    }

    func selectPreviousTab() {
        withTab { $0.selectPreviousTab() }
    }

    private func withTab(_ action: (WeaveThread) -> Void) {
        guard let thread = activeThread else { return }
        dismissSearch()
        action(thread)
        focusActiveSurface()
    }

    // MARK: - Thread navigation

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
        switchTo(threads[(idx + 1) % threads.count])
    }

    func selectPreviousThread() {
        let threads = allThreads
        guard !threads.isEmpty else { return }
        guard let idx = threads.firstIndex(where: { $0.id == activeThreadID }) else {
            if let last = threads.last { switchTo(last) }
            return
        }
        switchTo(threads[(idx - 1 + threads.count) % threads.count])
    }

    func selectNextActiveThread() {
        let threads = allThreads
        guard let currentIdx = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        let count = threads.count
        for offset in 1 ..< count {
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
        for offset in 1 ..< count {
            let thread = threads[(currentIdx - offset + count) % count]
            if thread.agentStatus != .idle {
                switchTo(thread)
                return
            }
        }
    }

    // MARK: - Private

    private func ensureSurfaces(for thread: WeaveThread) {
        thread.restoreSurfaces(onClose: { [weak self, weak thread] tab in
            guard let self, let thread else { return }
            self.closeTab(tab, in: thread)
        })
    }

    private func findPane(id paneIDString: String) -> (Pane, WeaveThread)? {
        for repo in repos {
            for thread in repo.threads {
                for tab in thread.tabs {
                    if let pane = tab.panes.first(where: { $0.id.uuidString == paneIDString }) {
                        return (pane, thread)
                    }
                }
            }
        }
        return nil
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed.toggle() }
    }

    func dismissSearch() {
        search.dismiss(surface: activeThread?.activeTab?.activePane?.surfaceView?.surface)
    }

    func focusActiveSurface() {
        guard let thread = activeThread,
              let tab = thread.activeTab,
              let pane = tab.activePane,
              let surface = pane.surfaceView else { return }
        DispatchQueue.main.async {
            surface.window?.makeFirstResponder(surface)
        }
    }

}
