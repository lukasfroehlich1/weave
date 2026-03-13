import Foundation

@MainActor
@Observable
class Tab: Identifiable, Codable {
    let id: UUID
    var title: String = "Terminal"
    var panes: [Pane] = []
    var activePaneID: UUID?

    var activePane: Pane? {
        panes.first { $0.id == activePaneID }
    }

    var agentStatus: AgentStatus {
        if panes.contains(where: { $0.agentStatus == .working }) { return .working }
        if panes.contains(where: { $0.agentStatus == .needsInput }) { return .needsInput }
        if panes.contains(where: { $0.agentStatus == .review }) { return .review }
        return .idle
    }

    enum CodingKeys: String, CodingKey {
        case id, title, panes, activePaneID
    }

    init(id: UUID = UUID()) {
        self.id = id
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Terminal"
        panes = try c.decodeIfPresent([Pane].self, forKey: .panes) ?? []
        activePaneID = try c.decodeIfPresent(UUID.self, forKey: .activePaneID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(panes, forKey: .panes)
        try c.encodeIfPresent(activePaneID, forKey: .activePaneID)
    }
}
