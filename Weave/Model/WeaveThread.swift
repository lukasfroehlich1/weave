import Foundation

@Observable
class WeaveThread: Identifiable {
    let id: UUID
    var name: String
    var worktreePath: String
    var branch: String
    var tabs: [TerminalTab] = []
    var activeTabID: UUID?
    var createdAt: Date
    var lastActiveAt: Date
    var prInfo: PRInfo?

    var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabID }
    }

    var agentStatus: AgentStatus {
        if tabs.contains(where: { $0.agentStatus == .working }) { return .working }
        if tabs.contains(where: { $0.agentStatus == .needsInput }) { return .needsInput }
        if tabs.contains(where: { $0.agentStatus == .review }) { return .review }
        return .idle
    }

    init(name: String, worktreePath: String, branch: String) {
        self.id = UUID()
        self.name = name
        self.worktreePath = worktreePath
        self.branch = branch
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}
