import Foundation

@MainActor
@Observable
class WeaveThread: Identifiable, Codable {
    let id: UUID
    var name: String
    var worktreePath: String
    var branch: String
    var isMainWorktree: Bool = false
    var tabs: [Tab] = []
    var activeTabID: UUID?
    var createdAt: Date
    var lastActiveAt: Date
    var cachedPR: CachedPR?

    /// Transient
    var prInfo: PRInfo?

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var agentStatus: AgentStatus {
        if tabs.contains(where: { $0.agentStatus == .working }) { return .working }
        if tabs.contains(where: { $0.agentStatus == .needsInput }) { return .needsInput }
        if tabs.contains(where: { $0.agentStatus == .review }) { return .review }
        return .idle
    }

    // MARK: - PR

    func refreshPR(repoPath: String) async {
        guard !isMainWorktree else { return }
        let branch = self.branch
        let newPR = await Task.detached {
            PRMonitor.fetchPR(repoPath: repoPath, branch: branch)
        }.value
        if prInfo != newPR {
            prInfo = newPR
            if let pr = newPR {
                cachedPR = CachedPR(
                    number: pr.number,
                    url: pr.url.absoluteString,
                    state: pr.state.rawValue
                )
            } else {
                cachedPR = nil
            }
        }
    }

    func restorePRFromCache() {
        guard let cached = cachedPR,
              let url = URL(string: cached.url),
              let state = PRState(rawValue: cached.state) else { return }
        prInfo = PRInfo(number: cached.number, url: url, state: state)
    }

    // MARK: - Tab management

    @discardableResult
    func addTab(onClose: @escaping @MainActor (Tab) -> Void) -> Tab {
        let tab = Tab()
        let pane = Pane()

        pane.attachSurface(workingDirectory: worktreePath) { surface in
            configureSurfaceCallbacks(surface, for: tab, onClose: onClose)
        }

        tab.panes = [pane]
        tab.activePaneID = pane.id
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func closeTab(_ tab: Tab) {
        for pane in tab.panes {
            pane.saveScrollback()
            AgentStatusMonitor.removeStatus(tabID: pane.id.uuidString)
            pane.tearDownSurface()
        }

        tabs.removeAll { $0.id == tab.id }

        if activeTabID == tab.id {
            activeTabID = tabs.last?.id
        }
    }

    func restoreSurfaces(onClose: @escaping @MainActor (Tab) -> Void) {
        if tabs.isEmpty {
            addTab(onClose: onClose)
            return
        }

        for tab in tabs {
            for pane in tab.panes where pane.surfaceView == nil {
                pane.attachSurface(
                    workingDirectory: worktreePath,
                    command: pane.replayCommand
                ) { surface in
                    configureSurfaceCallbacks(surface, for: tab, onClose: onClose)
                }
            }
        }
    }

    func removeAllSurfaces() {
        for tab in tabs {
            for pane in tab.panes {
                AgentStatusMonitor.removeStatus(tabID: pane.id.uuidString)
                pane.removeScrollback()
                pane.tearDownSurface()
            }
        }
        tabs.removeAll()
    }

    func clearReviewStatus() {
        for tab in tabs {
            for pane in tab.panes where pane.agentStatus == .review {
                pane.agentStatus = .idle
            }
        }
    }

    // MARK: - Surface callbacks

    private func configureSurfaceCallbacks(
        _ surface: GhosttySurfaceView,
        for tab: Tab,
        onClose: @escaping @MainActor (Tab) -> Void
    ) {
        surface.onTitleChange = { [weak self, weak tab] title in
            guard let self, let tab else { return }
            tab.title = WeaveHelpers.displayTitle(title, worktreePath: self.worktreePath)
        }
        surface.onClose = { [weak tab] in
            guard let tab else { return }
            onClose(tab)
        }
        surface.onInput = { [weak self] in
            self?.lastActiveAt = .now
        }
    }

    // MARK: - Tab navigation

    func selectNextTab() {
        guard tabs.count > 1,
              let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activeTabID = tabs[(idx + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1,
              let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activeTabID = tabs[(idx - 1 + tabs.count) % tabs.count].id
    }

    func selectTab(at index: Int) {
        guard !tabs.isEmpty else { return }
        let idx = min(index, tabs.count - 1)
        activeTabID = tabs[idx].id
    }

    func selectLastTab() {
        activeTabID = tabs.last?.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, worktreePath, branch, isMainWorktree, tabs, activeTabID, createdAt, lastActiveAt, cachedPR
    }

    init(name: String, worktreePath: String, branch: String, isMainWorktree: Bool = false) {
        self.id = UUID()
        self.name = name
        self.worktreePath = worktreePath
        self.branch = branch
        self.isMainWorktree = isMainWorktree
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        worktreePath = try c.decode(String.self, forKey: .worktreePath)
        branch = try c.decode(String.self, forKey: .branch)
        isMainWorktree = try c.decodeIfPresent(Bool.self, forKey: .isMainWorktree) ?? false
        tabs = try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        activeTabID = try c.decodeIfPresent(UUID.self, forKey: .activeTabID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? Date()
        cachedPR = try c.decodeIfPresent(CachedPR.self, forKey: .cachedPR)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(worktreePath, forKey: .worktreePath)
        try c.encode(branch, forKey: .branch)
        try c.encode(isMainWorktree, forKey: .isMainWorktree)
        try c.encode(tabs, forKey: .tabs)
        try c.encodeIfPresent(activeTabID, forKey: .activeTabID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastActiveAt, forKey: .lastActiveAt)
        try c.encodeIfPresent(cachedPR, forKey: .cachedPR)
    }
}
